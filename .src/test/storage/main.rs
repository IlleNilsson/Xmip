//! Xmip Storage as a node meets it: the test Storage node — its runtime
//! database in `RocksDB` on disk in the test's directory, its administration
//! and audit databases in SQLite in memory (the owner, 2026-10-01: *for testing
//! purposes the Xmip Nodes of Storage type can use SQLite in memory for
//! administration and `RocksDB` for runtime*) — in processes of its own,
//! killed hard, and reached over Xmip's TLS. What every test here opens and
//! starts is here once; each test is in the file named for what it proves:
//!
//! - `kill.rs`: a write acknowledged is there after the process is killed,
//!   and a hand-on killed at any moment is all there or not at all;
//! - `served.rs`: a node reaches a Storage node process over mutual TLS,
//!   carries on through the next when one is killed, and the audit keeper
//!   moves each record once; and the latency of a write, measured idle,
//!   locally and over TLS (`runtime-model.md` section 3, *What proves it*).
//!
//! A child is this same test program, started again with
//! [`CHILD`] naming what it does: [`child`] is the test that does it, and
//! does nothing where nothing is named.

mod kill;
mod served;

use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdout, Command, Stdio};
use std::sync::Arc;
use std::sync::mpsc::{self, Receiver};
use std::time::Duration;

use xmip_core::{JourneyId, MessageId};
use xmip_persist::storage::{
    Embedded, HandOn, JourneyRecord, MessageRecord, StorageServer, XmipStorage,
};
use xmip_persist_rocksdb::RocksDb;
use xmip_persist_sqlite::Sqlite;
use xmip_secret::{Held, KekName, KeyStore};

/// The environment variable naming what a child does.
const CHILD: &str = "XMIP_STORAGE_CHILD";
/// The environment variable naming the directory a child keeps its node in.
const PLACE: &str = "XMIP_STORAGE_PLACE";

/// The test Storage node.
type TestNode = Embedded<RocksDb, Sqlite>;

/// A directory of a test's own, empty.
fn directory(test: &str) -> PathBuf {
    let path = std::env::temp_dir().join(format!("xmip-storage-{test}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&path);
    std::fs::create_dir_all(&path).expect("directory");
    path
}

/// The platform's key store over `keys` (ADR-0063 clause 4), so a child
/// and the test that reopens what it wrote unwrap the same data key.
fn keys(keys: &Path) -> Box<dyn KeyStore> {
    #[cfg(windows)]
    let store = Held::new(xmip_secret_dpapi::Dpapi::new(keys));
    #[cfg(not(windows))]
    let store = Held::new(xmip_secret_file::KeyFile::new(keys));
    Box::new(store)
}

/// The test Storage node in `place`, its administration and audit
/// databases in memory.
fn test_node(place: &Path) -> TestNode {
    let administration = Sqlite::in_memory().expect("the administration database");
    let audit = Sqlite::in_memory().expect("the audit database");
    test_node_over(place, administration, audit)
}

/// The test Storage node in `place` over `administration` and `audit`.
fn test_node_over(place: &Path, administration: Sqlite, audit: Sqlite) -> TestNode {
    std::fs::create_dir_all(place.join("key")).expect("its directory");
    let runtime = RocksDb::open(&place.join("runtime")).expect("the runtime database");
    let kek = KekName::new("storage").expect("a name");
    let keys = keys(&place.join("key"));
    Embedded::open(runtime, administration, audit, keys.as_ref(), &kek)
        .expect("the test Storage node")
}

/// The Journey numbered `number` in a test.
fn journey(number: u64) -> JourneyId {
    JourneyId::new(0x0199_0000_0000_7000_8000_0000_0000_0000 | u128::from(number))
}

/// The hand-on of Journey `number`: its result, three Messages it made,
/// and the Journey that goes on from it.
fn hand_on(number: u64, claim: xmip_persist::storage::Claim) -> HandOn {
    HandOn {
        claim,
        result: JourneyRecord {
            journey: journey(number),
            body: format!("routed {number}").into_bytes(),
            facts: xmip_persist::storage::JourneyFacts::default(),
        },
        messages: (0..3)
            .map(|part| MessageRecord {
                message: message(number, part),
                body: vec![b'm'; 512],
                facts: xmip_persist::storage::MessageFacts::default(),
            })
            .collect(),
        next: vec![JourneyRecord {
            journey: journey(number + 1_000_000),
            body: format!("to send {number}").into_bytes(),
            facts: xmip_persist::storage::JourneyFacts::default(),
        }],
        leaves: Vec::new(),
        queued: Vec::new(),
        requeued: Vec::new(),
        kept_for_nanos: None,
    }
}

fn message(number: u64, part: u64) -> MessageId {
    MessageId::new(0x0199_0000_0000_7000_9000_0000_0000_0000 | u128::from(number * 3 + part))
}

/// This test program started again as a child doing `what` in `place`.
fn spawn(what: &str, place: &Path) -> (Child, Receiver<String>) {
    let mut child = Command::new(std::env::current_exe().expect("this program"))
        .args(["child", "--exact", "--nocapture", "--test-threads=1"])
        .env(CHILD, what)
        .env(PLACE, place)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("a child");
    let lines = said(child.stdout.take().expect("its output"));
    (child, lines)
}

/// What a child says, line by line, as it says it.
fn said(output: ChildStdout) -> Receiver<String> {
    let (tell, told) = mpsc::channel();
    std::thread::spawn(move || {
        for line in BufReader::new(output).lines().map_while(Result::ok) {
            if tell.send(line).is_err() {
                return;
            }
        }
    });
    told
}

/// What follows `opening` in the next line a child says with it, within
/// `within`.
fn heard(lines: &Receiver<String>, opening: &str, within: Duration) -> String {
    let deadline = std::time::Instant::now() + within;
    loop {
        let left = deadline.saturating_duration_since(std::time::Instant::now());
        let line = lines
            .recv_timeout(left)
            .unwrap_or_else(|_| panic!("the child never said '{opening}'"));
        // The test harness says `test child ... ` before the child's first
        // line, on the same line.
        if let Some(at) = line.find(opening) {
            return line[at + opening.len()..].trim().to_string();
        }
    }
}

/// A line said and on its way at once.
fn say(line: &str) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{line}");
    let _ = out.flush();
}

/// The child: does what [`CHILD`] names, and nothing where nothing is named.
#[test]
fn child() {
    let (Ok(what), Ok(place)) = (std::env::var(CHILD), std::env::var(PLACE)) else {
        return;
    };
    let place = PathBuf::from(place);
    let node = Arc::new(test_node(&place));
    match what.as_str() {
        "write" => kill::write_until_killed(node.as_ref()),
        "hand-on" => kill::hand_on_until_killed(node.as_ref()),
        "serve" => {
            let served = served::serve(node, &place);
            say(&format!("serving {}", served.address()));
            // Until the test closes this child's input, or kills it.
            let _ = std::io::stdin().lines().count();
            StorageServer::stop(served);
        }
        other => panic!("no child does '{other}'"),
    }
}

/// The node's operations, timed: each write's latency, sorted.
fn timed(node: &dyn XmipStorage, writes: u64, body: &[u8]) -> Vec<Duration> {
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
fn percentiles(taken: &[Duration]) -> (Duration, Duration) {
    let at = |share: usize| taken[(taken.len() * share / 100).min(taken.len() - 1)];
    (at(50), at(99))
}
