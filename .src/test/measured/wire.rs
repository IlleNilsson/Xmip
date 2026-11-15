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

use xmip_core::latency::spread;
use xmip_persist::Engine;
use xmip_persist::storage::client::PASS_OVER;
use xmip_persist::storage::standby::{BEAT, KEPT, SILENCE, Timings};
use xmip_persist::storage::{
    StorageClient, StorageNode, StorageServer, UNWAITED, WRITER_KEPT, XmipStorage,
};
use xmip_persist_rocksdb::RocksDb;
use xmip_persist_sqlite::Sqlite;
use xmip_secret::KekName;

use super::authority::{authority, issue};
use super::node::{directory, journey, keys, test_node};

/// Each connect and each read a node makes of a Storage node.
pub(super) const TIMEOUT: Duration = Duration::from_secs(10);

/// How many of each call are timed.
const CALLS: u64 = 500;

/// One Storage node of `listed`, at `listener`, on `RocksDB` and `SQLite`
/// in memory in `place`, served; it settles once started, every one listed
/// answering (`woken.rs` too).
pub(super) fn storage_node(
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
        unwaited: UNWAITED,
        writer_kept: WRITER_KEPT,
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
    (node, server)
}

/// Two Storage nodes in `test`, each served, settled with the first the
/// primary and the other its standby, and their addresses: what a node
/// lists in `[storage] nodes`.
pub(super) fn primary_and_standby(
    test: &Path,
) -> (Vec<(Arc<StorageNode>, StorageServer)>, Vec<String>) {
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
        nodes.push(storage_node(&at, (listener, &listed), &issue(test)));
    }
    // Both served before either starts: a Storage node is promoted only
    // where every one listed answers (ADR-0056, amendment 2026-11-08).
    for (node, _) in &nodes {
        node.start(Duration::from_secs(10)).expect("settled");
    }
    assert!(nodes[0].0.is_primary(), "{}", nodes[0].0.said());
    (nodes, listed)
}

/// Each of `CALLS` calls `call` makes of the node in process and then of
/// the one over the wire, in turn, so each sees the machine as the other
/// does: each call's time, in the order measured, printed under `what`, and
/// the fastest of five of each (`xmip_core::latency::spread`). Until
/// 2026-11-15 the in-process calls were timed before the wire's, and the
/// medians held.
fn beside(
    what: &str,
    [local, wire]: [&dyn XmipStorage; 2],
    call: impl Fn(&dyn XmipStorage, u64),
) -> [Duration; 2] {
    let mut taken = [Vec::new(), Vec::new()];
    for number in 0..CALLS {
        for (place, node) in [local, wire].into_iter().enumerate() {
            let started = Instant::now();
            call(node, number);
            taken[place].push(started.elapsed());
        }
    }
    let [local, wire] = taken;
    [
        spread(&format!("{what}, in process"), local).fastest_of_five,
        spread(&format!("{what}, over the wire to the primary"), wire).fastest_of_five,
    ]
}

/// Journey `number` written with `body`.
fn write(node: &dyn XmipStorage, number: u64, body: &[u8]) {
    let record = xmip_persist::storage::JourneyRecord {
        journey: journey(number),
        body: body.to_vec(),
        facts: xmip_persist::storage::JourneyFacts::default(),
    };
    node.write_journey(&record).expect("written");
}

#[test]
fn a_storage_call_over_the_wire_costs_less_than_a_millisecond_beyond_its_load() {
    let test = directory("wire");
    authority(&test);
    let body = vec![b'x'; 1024];

    let local = test_node(&test.join("local"));
    let (nodes, listed) = primary_and_standby(&test);
    let client = StorageClient::new(&listed, &issue(&test), TIMEOUT, PASS_OVER).expect("a client");
    let both: [&dyn XmipStorage; 2] = [&local, &client];
    // A read is the wire's own cost; a write carries its sync, the disk's
    // time, which the same write in process carries beside it. Neither is
    // a wake a plain wake could stand for, so each is held beside the
    // other, the fastest of five each.
    let [local_write, wire_write] = beside("a write and its sync", both, |node, number| {
        write(node, number, &body);
    });
    let [local_read, wire_read] = beside("a read", both, |node, number| {
        let read = node.read_journey(journey(number)).expect("read");
        assert!(read.is_some(), "{number} was written");
    });
    let deadline = Instant::now() + Duration::from_secs(10);
    while nodes[1].0.standing().next != nodes[0].0.standing().next && Instant::now() < deadline {
        std::thread::yield_now();
    }
    let copied = nodes[1].0.standing().next == nodes[0].0.standing().next;
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
