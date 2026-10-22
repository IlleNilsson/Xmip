//! What a Storage call costs over the wire, against the millisecond rule
//! (CONTRIBUTING: *anything that takes more than a millisecond, apart from
//! the load it carries, is a defect*): a node reaching the primary of two
//! Storage nodes over Xmip's mutual TLS on loopback, its standby copying
//! every write behind it, beside the same calls of a Storage node in
//! process. A read is the wire's own cost; a write carries its sync, which
//! is load, measured in process beside it (`runtime-model.md` section 3,
//! *What proves it*).

use std::net::TcpListener;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, Instant};

use xmip_persist::Engine;
use xmip_persist::storage::client::PASS_OVER;
use xmip_persist::storage::standby::{BEAT, KEPT, SILENCE, Timings};
use xmip_persist::storage::{StorageClient, StorageNode, StorageServer, XmipStorage};
use xmip_persist_rocksdb::RocksDb;
use xmip_persist_sqlite::Sqlite;
use xmip_secret::KekName;

use super::served::{authority, issue};
use super::{directory, journey, keys, percentiles, test_node, timed};

/// Each connect and each read a node makes of a Storage node.
const TIMEOUT: Duration = Duration::from_secs(10);

/// How many of each call are timed.
const CALLS: u64 = 500;

/// One Storage node of `listed`, at `listener`, on `RocksDB` and `SQLite`
/// in memory in `place`, served and settled.
fn storage_node(
    place: &Path,
    (listener, listed): (TcpListener, &[String]),
    identity: &xmip_tls::Identity,
) -> (Arc<StorageNode>, StorageServer) {
    std::fs::create_dir_all(place).expect("its directory");
    let runtime: Arc<dyn Engine> =
        Arc::new(RocksDb::open(&place.join("runtime")).expect("the runtime database"));
    let administration: Arc<dyn Engine> = Arc::new(Sqlite::in_memory().expect("administration"));
    let audit: Arc<dyn Engine> = Arc::new(Sqlite::in_memory().expect("audit"));
    let kept = (
        Arc::from(keys(&place.join("key"))),
        KekName::new("storage").expect("a name"),
    );
    let timings = Timings {
        beat: BEAT,
        silence: SILENCE,
        timeout: TIMEOUT,
        pass_over: PASS_OVER,
        kept: KEPT,
    };
    let node = StorageNode::new(
        [runtime, administration, audit],
        kept,
        listed,
        identity,
        timings,
    )
    .expect("a Storage node");
    let server = StorageServer::several(&node, listener, identity).expect("served");
    node.start(Duration::from_secs(10)).expect("settled");
    (node, server)
}

/// How long each of `CALLS` reads of what [`timed`] wrote takes, sorted.
fn reads(node: &dyn XmipStorage) -> Vec<Duration> {
    let mut taken: Vec<Duration> = (0..CALLS)
        .map(|number| {
            let started = Instant::now();
            let read = node.read_journey(journey(number)).expect("read");
            let taken = started.elapsed();
            assert!(read.is_some(), "{number} was written");
            taken
        })
        .collect();
    taken.sort();
    taken
}

#[test]
fn a_storage_call_over_the_wire_costs_less_than_a_millisecond_beyond_its_load() {
    let test = directory("wire");
    authority(&test);
    let body = vec![b'x'; 1024];

    let local = test_node(&test.join("local"));
    let (local_write, _) = percentiles(&timed(&local, CALLS, &body));
    let (local_read, _) = percentiles(&reads(&local));

    let listeners: Vec<TcpListener> = (0..2)
        .map(|_| TcpListener::bind("127.0.0.1:0").expect("bound"))
        .collect();
    let listed: Vec<String> = listeners
        .iter()
        .map(|listener| listener.local_addr().expect("an address").to_string())
        .collect();
    let mut nodes = Vec::new();
    for (place, listener) in listeners.into_iter().enumerate() {
        let at = test.join(format!("storage-{place}"));
        nodes.push(storage_node(&at, (listener, &listed), &issue(&test)));
    }
    assert!(nodes[0].0.is_primary(), "{}", nodes[0].0.said());
    let client = StorageClient::new(&listed, &issue(&test), TIMEOUT, PASS_OVER).expect("a client");
    let (wire_write, slowest_write) = percentiles(&timed(&client, CALLS, &body));
    let (wire_read, slowest_read) = percentiles(&reads(&client));
    let deadline = Instant::now() + Duration::from_secs(10);
    while nodes[1].0.standing().next != nodes[0].0.standing().next && Instant::now() < deadline {
        std::thread::yield_now();
    }
    let copied = nodes[1].0.standing().next == nodes[0].0.standing().next;

    eprintln!(
        "LATENCY a read: in process median {local_read:?}; over the wire to the primary median \
         {wire_read:?}, 99th percentile {slowest_read:?}"
    );
    eprintln!(
        "LATENCY a write and its sync: in process median {local_write:?}; over the wire to the \
         primary, its standby copying, median {wire_write:?}, 99th percentile {slowest_write:?}; \
         the standby holding every write: {copied}"
    );
    assert!(copied, "{}", nodes[1].0.said());
    let read_beyond = wire_read.saturating_sub(local_read);
    let write_beyond = wire_write.saturating_sub(local_write);
    assert!(
        read_beyond < Duration::from_millis(1),
        "a read over the wire took {read_beyond:?} beyond one in process"
    );
    assert!(
        write_beyond < Duration::from_millis(1),
        "a write over the wire took {write_beyond:?} beyond one in process, its sync the load"
    );
    for (node, server) in nodes {
        node.stop();
        server.stop();
    }
    let _ = std::fs::remove_dir_all(&test);
}
