//! A Journey one node puts in a queue, told to another node waiting on that
//! queue, against the millisecond rule (open problem 46; ADR-0028,
//! amendment 2026-11-12): two nodes reaching the primary of two Storage
//! nodes over Xmip's mutual TLS on loopback, its standby copying behind it —
//! one publishing a Journey into a queue, then handing each on into another,
//! the other waiting on that queue (`XmipStorage::wait_queues`), as a send
//! step and a Work Process step wait on theirs. What it holds: how long after
//! the write was answered the waiting node is told, the median under a
//! millisecond. Until 2026-11-12 the waiting node found it at its next scan,
//! a second by default.

use std::sync::Arc;
use std::time::{Duration, Instant};

use xmip_core::{AuditId, MessageId};
use xmip_persist::storage::client::PASS_OVER;
use xmip_persist::storage::{
    AuditEntry, AuditFacts, HandOn, Hold, JourneyFacts, JourneyRecord, MessageFacts, MessageRecord,
    Position, Publication, StorageClient, Waiter, XmipStorage,
};

use super::authority::{authority, issue};
use super::node::{directory, journey, percentiles};
use super::wire::{TIMEOUT, primary_and_standby};

/// How many of each write are timed.
const ROUNDS: u64 = 200;

/// The queue each Journey is published into: a Send Port's.
const PUBLISHED: u128 = 7;

/// The queue each is handed on into: a Work Process's, or another Port's.
const ONWARD: u128 = 9;

/// How long a wait may last: far longer than any is told within.
const BOUND: Duration = Duration::from_secs(10);

/// The Journey numbered `number` published, held in [`PUBLISHED`].
fn publication(number: u64) -> Publication {
    let id = journey(number);
    Publication {
        message: MessageRecord {
            message: MessageId::new(id.value()),
            body: b"order".to_vec(),
            facts: MessageFacts::default(),
        },
        journeys: vec![JourneyRecord {
            journey: id,
            body: b"waiting".to_vec(),
            facts: JourneyFacts::default(),
        }],
        held: vec![Hold {
            queue: PUBLISHED,
            journey: id,
            body: Vec::new(),
        }],
        dead: None,
        audit: AuditEntry {
            id: AuditId::new(id.value()),
            body: b"published".to_vec(),
            audited: None,
            facts: AuditFacts::default(),
        },
        claims: Vec::new(),
        lease_nanos: 0,
    }
}

/// The Journey numbered `number` taken out of [`PUBLISHED`] by `holder` and
/// handed on into [`ONWARD`].
fn handed_on(writing: &StorageClient, holder: &str, number: u64) {
    let id = journey(number);
    let claim = writing.claim(id, holder, u128::from(number) + 1, TIMEOUT);
    let hand_on = HandOn {
        claim: claim.expect("asked").expect("claimed"),
        result: JourneyRecord {
            journey: id,
            body: b"onward".to_vec(),
            facts: JourneyFacts::default(),
        },
        messages: Vec::new(),
        next: Vec::new(),
        leaves: vec![PUBLISHED],
        queued: vec![Hold {
            queue: ONWARD,
            journey: id,
            body: Vec::new(),
        }],
        requeued: Vec::new(),
        failed: None,
        cleared: Vec::new(),
        waits: None,
        kept_for_nanos: None,
    };
    assert!(writing.hand_on(&hand_on).expect("handed on"));
}

/// For each of [`ROUNDS`] writes `write` makes, each putting one Journey in
/// `queue`: how long after it was asked `waiting`, waiting on `queue` where
/// it stood before it, was told, how long the write took to be answered,
/// and how long the telling took beyond that answer; each sorted.
fn told(waiting: &Arc<StorageClient>, queue: u128, write: impl Fn(u64)) -> [Vec<Duration>; 3] {
    let waiter = Arc::new(Waiter::new());
    let mut taken = [Vec::new(), Vec::new(), Vec::new()];
    for number in 0..ROUNDS {
        let seen = [Position {
            queue,
            next: number,
        }];
        let (asking, held) = (Arc::clone(waiting), Arc::clone(&waiter));
        let woken = std::thread::spawn(move || {
            let moved = asking.wait_queues(&seen, BOUND, &held).expect("answered");
            (moved, Instant::now())
        });
        let asked = Instant::now();
        write(number);
        let answered = Instant::now();
        let (moved, at) = woken.join().expect("woken");
        let now = Position {
            queue,
            next: number + 1,
        };
        assert_eq!(moved, [now], "told where the queue stands");
        taken[0].push(at.saturating_duration_since(asked));
        taken[1].push(answered - asked);
        taken[2].push(at.saturating_duration_since(answered));
    }
    for each in &mut taken {
        each.sort();
    }
    taken
}

/// What [`told`] measured, said, and the telling beyond the write's answer,
/// the median, for the millisecond rule.
fn said(what: &str, [told, wrote, beyond]: &[Vec<Duration>; 3]) -> Duration {
    let ((told, slowest), (wrote, _)) = (percentiles(told), percentiles(wrote));
    let (beyond, slowest_beyond) = percentiles(beyond);
    eprintln!(
        "LATENCY a node told of {what} another node wrote into a queue it waits on: from the \
         write asked median {told:?} (99th percentile {slowest:?}), the write answered in \
         {wrote:?}; beyond its answer median {beyond:?} (99th percentile {slowest_beyond:?})"
    );
    beyond
}

#[test]
fn a_journey_another_node_puts_in_a_queue_is_told_within_a_millisecond_of_its_write() {
    let test = directory("woken");
    authority(&test);
    let (nodes, listed) = primary_and_standby(&test);
    let client = || StorageClient::new(&listed, &issue(&test), TIMEOUT, PASS_OVER).expect("a node");
    let (writer, watching) = (client(), Arc::new(client()));
    let holder = super::test_cluster().node_scope(0);

    let published = told(&watching, PUBLISHED, |number| {
        writer.publish(publication(number)).expect("published");
    });
    let onward = told(&watching, ONWARD, |number| {
        handed_on(&writer, &holder, number);
    });
    let published = said("a Publication", &published);
    let onward = said("a hand-on", &onward);
    let millisecond = Duration::from_millis(1);
    assert!(
        published < millisecond,
        "a Publication told after {published:?}"
    );
    assert!(onward < millisecond, "a hand-on told after {onward:?}");
    for (node, server) in nodes {
        node.stop();
        server.stop();
    }
    let _ = std::fs::remove_dir_all(&test);
}
