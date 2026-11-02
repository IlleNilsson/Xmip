//! The test Storage node — its runtime database in `RocksDB` on disk in the
//! test's directory, its administration and audit databases in SQLite in
//! memory — and the Journeys a test writes to it, timed: what the Storage
//! tests and the root's timing program (`.src/test/measured/wire.rs`) both
//! open and write. Shared, not copied.

use std::path::{Path, PathBuf};
use std::time::Duration;

use xmip_core::JourneyId;
use xmip_persist::storage::{Embedded, JourneyRecord, XmipStorage};
use xmip_persist_rocksdb::RocksDb;
use xmip_persist_sqlite::Sqlite;
use xmip_secret::{Held, KekName, KeyStore};

/// The test Storage node.
pub type TestNode = Embedded<RocksDb, Sqlite>;

/// A directory of a test's own, empty.
pub fn directory(test: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("xmip-storage-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&path);
    std::fs::create_dir_all(&path).expect("directory");
    path
}

/// The platform's key store over `keys` (ADR-0063 clause 4), so a child
/// and the test that reopens what it wrote unwrap the same data key.
pub fn keys(keys: &Path) -> Box<dyn KeyStore> {
    #[cfg(windows)]
    let store = Held::new(xmip_secret_dpapi::Dpapi::new(keys));
    #[cfg(not(windows))]
    let store = Held::new(xmip_secret_file::KeyFile::new(keys));
    Box::new(store)
}

/// The test Storage node in `place`, its administration and audit
/// databases in memory.
pub fn test_node(place: &Path) -> TestNode {
    let administration = Sqlite::in_memory().expect("the administration database");
    let audit = Sqlite::in_memory().expect("the audit database");
    test_node_over(place, administration, audit)
}

/// The test Storage node in `place` over `administration` and `audit`.
pub fn test_node_over(place: &Path, administration: Sqlite, audit: Sqlite) -> TestNode {
    // The key directory is the key store's to make: it makes it private,
    // and a directory made here with the default mode it would refuse
    // (ADR-0063 clause 4).
    std::fs::create_dir_all(place).expect("its directory");
    let runtime = RocksDb::open(&place.join("runtime")).expect("the runtime database");
    let kek = KekName::new("storage").expect("a name");
    let keys = keys(&place.join("key"));
    Embedded::open(runtime, administration, audit, keys.as_ref(), &kek)
        .expect("the test Storage node")
}

/// The Journey numbered `number` in a test.
pub fn journey(number: u64) -> JourneyId {
    JourneyId::new(0x0199_0000_0000_7000_8000_0000_0000_0000 | u128::from(number))
}

/// The node's operations, timed: each write's latency, sorted.
pub fn timed(node: &dyn XmipStorage, writes: u64, body: &[u8]) -> Vec<Duration> {
    let mut taken: Vec<Duration> = (0..writes)
        .map(|number| {
            let record = JourneyRecord {
                journey: journey(number),
                body: body.to_vec(),
                facts: xmip_persist::storage::JourneyFacts::default(),
            };
            let started = std::time::Instant::now();
            node.write_journey(&record).expect("written");
            started.elapsed()
        })
        .collect();
    taken.sort();
    taken
}

/// The median and the 99th percentile of what [`timed`] measured.
pub fn percentiles(taken: &[Duration]) -> (Duration, Duration) {
    let at = |share: usize| taken[(taken.len() * share / 100).min(taken.len() - 1)];
    (at(50), at(99))
}
