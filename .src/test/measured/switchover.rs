//! A primary Storage node stopped in order under load, measured on Storage
//! nodes as they are deployed (open problem 143; ADR-0056, amendment
//! 2026-11-24): three of them, each its runtime database in `RocksDB` and its
//! administration and audit databases in `SQLite`, all on disk in the
//! test's directory, its data keys sealed under the platform's own key store
//! (DPAPI on Windows, a key file elsewhere), each keeping its certificate
//! across its restarts; and a node writing under load through them all the
//! while — several threads writing as a node's sends do, one waiting as its
//! membership always is. Persist's own timing program measures the hand-over
//! over engines and a key store in memory, two Storage nodes and no load
//! (`tests/measured/succession.rs`); a technology depends on its parent,
//! never the reverse, so the engines are linked here, where every one is.
//!
//! **Measured, and printed**, over a rolling restart, each Storage node
//! restarted only once every other follows ready, as the deploy restarts
//! them: the successor serving as the primary from the stop's start; each
//! writer's longest wait across each stop; a write's own time before the
//! first stop; and how many writes and waits were refused across the stops,
//! where the runtime's callers rest a whole bound on each. Nothing is held:
//! the disk's syncs and the key store's reads are load, and the in-memory
//! figure is the one held to the millisecond rule.

use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::time::{Duration, Instant};

use xmip_core::latency::{spin, spread};
use xmip_persist::Engine;
use xmip_persist::storage::client::{PASS_OVER, TIMEOUT};
use xmip_persist::storage::standby::{BEAT, Bootstrap, KEPT, SILENCE, Timings};
use xmip_persist::storage::{
    JourneyFacts, JourneyRecord, Position, StorageClient, StorageNode, StorageServer, UNWAITED,
    WRITER_KEPT, Waiter, XmipStorage,
};
use xmip_persist_rocksdb::RocksDb;
use xmip_persist_sqlite::Sqlite;
use xmip_secret::KekName;

use super::authority::{authority, issue};
use super::node::{directory, journey, keys};

/// How many Storage nodes the cluster lists.
const NODES: usize = 3;

/// How many primaries are stopped in order, each restarted after.
const STOPS: usize = 6;

/// How many threads of the node write all along.
const WRITERS: usize = 4;

/// How long a test waits for what it waits on: a Storage node restarted
/// opens its databases on disk and is copied on before it follows ready.
const WITHIN: Duration = Duration::from_secs(60);

/// How long a writer leaves a refused write before it asks again: its own
/// pace, so it is not load it makes on the nodes.
const AGAIN: Duration = Duration::from_micros(50);

/// A Storage node and its server.
type Served = (Arc<StorageNode>, StorageServer);

/// Until `holds`, or [`WITHIN`] passed.
fn until(holds: impl Fn() -> bool) -> bool {
    let deadline = Instant::now() + WITHIN;
    while Instant::now() < deadline {
        if holds() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    holds()
}

/// The Storage node in `place`, its databases on disk, its keys sealed by
/// the platform's key store, listed among `listed` and listening on
/// `listener`, presenting `identity`, bounded by the defaults a node's
/// `[tuning]` leaves; served, settling nothing until started.
fn deployed(
    place: &Path,
    (listener, listed): (TcpListener, &[String]),
    identity: &xmip_tls::Identity,
) -> Served {
    std::fs::create_dir_all(place).expect("its directory");
    let runtime: Arc<dyn Engine> =
        Arc::new(RocksDb::open(&place.join("runtime")).expect("the runtime database"));
    let administration: Arc<dyn Engine> =
        Arc::new(Sqlite::open(&place.join("administration.db")).expect("administration"));
    let audit: Arc<dyn Engine> = Arc::new(Sqlite::open(&place.join("audit.db")).expect("audit"));
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
    let engines = [runtime, administration, audit];
    let node = StorageNode::new(engines, kept, listed, identity, timings).expect("a Storage node");
    let server = StorageServer::several(&node, listener, identity).expect("served");
    (node, server)
}

/// Whether `node` follows its primary, ready: what the deploy waits for.
fn following(node: &StorageNode) -> bool {
    node.is_following() && node.bootstrap() == Bootstrap::Ready
}

/// The Storage nodes, each running or not; the addresses listed; and each
/// one's place and certificate, kept across its restarts.
struct Cluster {
    nodes: Vec<Option<Served>>,
    listed: Vec<String>,
    places: Vec<PathBuf>,
    identities: Vec<xmip_tls::Identity>,
}

/// The cluster: every Storage node served before any starts, each in its
/// place under `test`, with its own certificate.
fn cluster(test: &Path) -> Cluster {
    let listeners: Vec<TcpListener> = (0..NODES)
        .map(|_| TcpListener::bind("127.0.0.1:0").expect("bound"))
        .collect();
    let listed: Vec<String> = listeners
        .iter()
        .map(|listener| listener.local_addr().expect("an address").to_string())
        .collect();
    let places: Vec<PathBuf> = (0..NODES)
        .map(|at| test.join(format!("storage-{at}")))
        .collect();
    let identities: Vec<xmip_tls::Identity> = (0..NODES).map(|_| issue(test)).collect();
    let nodes: Vec<Option<Served>> = listeners
        .into_iter()
        .enumerate()
        .map(|(at, listener)| Some(deployed(&places[at], (listener, &listed), &identities[at])))
        .collect();
    for (node, _) in nodes.iter().flatten() {
        node.start(WITHIN).expect("settled");
    }
    Cluster {
        nodes,
        listed,
        places,
        identities,
    }
}

/// A Journey of a kilobyte, numbered `number`.
fn written(number: u64) -> JourneyRecord {
    JourneyRecord {
        journey: journey(number),
        body: vec![b'x'; 1024],
        facts: JourneyFacts::default(),
    }
}

/// What the node writing under load did: each writer's writes answered,
/// and when; and how many writes and waits were refused.
struct Load {
    going: Arc<AtomicBool>,
    count: Arc<AtomicUsize>,
    refused: Arc<AtomicUsize>,
    waits_refused: Arc<AtomicUsize>,
    writers: Vec<std::thread::JoinHandle<Vec<Instant>>>,
    waiting: std::thread::JoinHandle<()>,
}

impl Load {
    /// [`WRITERS`] threads writing through `client` all along, each from
    /// its own Journeys, and one waiting on a queue nothing writes.
    fn start(client: &Arc<StorageClient>) -> Self {
        let going = Arc::new(AtomicBool::new(true));
        let count = Arc::new(AtomicUsize::new(0));
        let refused = Arc::new(AtomicUsize::new(0));
        let waits_refused = Arc::new(AtomicUsize::new(0));
        let writers = (0..WRITERS)
            .map(|writer| {
                let (client, going) = (Arc::clone(client), Arc::clone(&going));
                let (count, refused) = (Arc::clone(&count), Arc::clone(&refused));
                std::thread::spawn(move || {
                    let mut answered = Vec::new();
                    let first = u64::try_from(writer).expect("a writer") << 40;
                    for number in first.. {
                        if !going.load(Ordering::SeqCst) {
                            break;
                        }
                        if client.write_journey(&written(number)).is_ok() {
                            answered.push(Instant::now());
                            count.fetch_add(1, Ordering::SeqCst);
                        } else {
                            refused.fetch_add(1, Ordering::SeqCst);
                            spin(AGAIN);
                        }
                    }
                    answered
                })
            })
            .collect();
        let waiting = {
            let (client, going) = (Arc::clone(client), Arc::clone(&going));
            let waits_refused = Arc::clone(&waits_refused);
            std::thread::spawn(move || {
                let waiter = Arc::new(Waiter::new());
                let seen = [Position::queue(9, 0)];
                while going.load(Ordering::SeqCst) {
                    let bound = (Duration::from_millis(200), 0);
                    if client.wait_queues(&seen, bound, &waiter).is_err() {
                        waits_refused.fetch_add(1, Ordering::SeqCst);
                        spin(AGAIN);
                    }
                }
            })
        };
        Self {
            going,
            count,
            refused,
            waits_refused,
            writers,
            waiting,
        }
    }

    /// Whether `more` writes were answered after `from`.
    fn moved(&self, from: usize, more: usize) -> bool {
        until(|| self.count.load(Ordering::SeqCst) >= from + more)
    }

    /// Stopped: each writer's writes answered, and the refusals counted.
    fn stop(self) -> (Vec<Vec<Instant>>, usize, usize) {
        self.going.store(false, Ordering::SeqCst);
        let answered = self
            .writers
            .into_iter()
            .map(|writer| writer.join().expect("written along"))
            .collect();
        self.waiting.join().expect("waited along");
        (
            answered,
            self.refused.load(Ordering::SeqCst),
            self.waits_refused.load(Ordering::SeqCst),
        )
    }
}

/// When the first of `standbys` serves as the primary, watched on a thread
/// of its own.
fn promoted(standbys: Vec<Arc<StorageNode>>) -> std::thread::JoinHandle<Instant> {
    std::thread::spawn(move || {
        while !standbys.iter().any(|node| node.is_primary()) {
            std::hint::spin_loop();
        }
        Instant::now()
    })
}

#[test]
fn a_primary_stopped_in_order_on_deployed_storage_nodes_under_load_is_measured() {
    let test = directory("switchover");
    authority(&test);
    let Cluster {
        mut nodes,
        listed,
        places,
        identities,
    } = cluster(&test);
    let client =
        Arc::new(StorageClient::new(&listed, &issue(&test), TIMEOUT, PASS_OVER).expect("a client"));
    let load = Load::start(&client);
    assert!(load.moved(0, 2_000), "no writes");
    let (mut stops, mut backs, mut took) = (Vec::new(), Vec::new(), Vec::new());
    for round in 0..STOPS {
        let primary = (0..NODES)
            .find(|at| {
                nodes[*at]
                    .as_ref()
                    .is_some_and(|(node, _)| node.is_primary())
            })
            .expect("a primary");
        let standbys: Vec<Arc<StorageNode>> = (0..NODES)
            .filter(|at| *at != primary)
            .map(|at| Arc::clone(&nodes[at].as_ref().expect("running").0))
            .collect();
        let ready = || standbys.iter().all(|node| following(node));
        assert!(
            until(ready),
            "round {round}: the standbys do not follow ready"
        );
        assert!(
            load.moved(load.count.load(Ordering::SeqCst), 200),
            "round {round}: writes do not go on"
        );
        let (node, server) = nodes[primary].take().expect("running");
        let watched = promoted(standbys);
        let began = Instant::now();
        node.stop();
        let at = watched.join().expect("watched");
        server.stop();
        drop(node);
        stops.push(began);
        took.push(at - began);
        let listener = TcpListener::bind(&listed[primary]).expect("bound again");
        let again = deployed(&places[primary], (listener, &listed), &identities[primary]);
        again.0.start(WITHIN).expect("settled again");
        nodes[primary] = Some(again);
        backs.push(Instant::now());
    }
    assert!(
        load.moved(load.count.load(Ordering::SeqCst), 200),
        "writes go on after the last stop"
    );
    let (answered, refused, waits_refused) = load.stop();

    let longest = |from: Instant, until: Option<&Instant>| {
        answered
            .iter()
            .flat_map(|writer| writer.windows(2))
            .filter(|pair| pair[1] > from && until.is_none_or(|until| pair[0] < *until))
            .map(|pair| pair[1] - pair[0])
            .max()
            .expect("a write answered after the stop")
    };
    // From each stop to the next; and apart, across the stop until its
    // former primary was back, opening its databases on disk, then from
    // then until the next stop, while it came back to follow its successor.
    let gaps: Vec<Duration> = stops
        .iter()
        .enumerate()
        .map(|(at, began)| longest(*began, stops.get(at + 1)))
        .collect();
    let across: Vec<Duration> = stops
        .iter()
        .zip(&backs)
        .map(|(began, back)| longest(*began, Some(back)))
        .collect();
    let after: Vec<Duration> = backs
        .iter()
        .enumerate()
        .map(|(at, back)| longest(*back, stops.get(at + 1)))
        .collect();
    let writes: Vec<Duration> = answered
        .iter()
        .flat_map(|writer| writer.windows(2))
        .filter(|pair| pair[1] < stops[0])
        .map(|pair| pair[1] - pair[0])
        .collect();
    let _printed = spread("deployed: a write, one after another, each writer", writes);
    let _printed = spread(
        "deployed: the successor serving, from the stop's start",
        took,
    );
    let _printed = spread(
        "deployed: writes waited across a primary's stop in order",
        gaps,
    );
    let _printed = spread(
        "deployed: of it, from the stop until the former primary was back",
        across,
    );
    let _printed = spread(
        "deployed: of it, as the former primary came back to follow",
        after,
    );
    println!(
        "deployed: {refused} writes and {waits_refused} waits refused across {STOPS} stops, \
         {WRITERS} writers"
    );
    for (node, server) in nodes.into_iter().flatten() {
        node.stop();
        server.stop();
    }
}
