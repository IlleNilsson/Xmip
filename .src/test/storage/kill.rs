//! A Storage node killed hard: every write it acknowledged is there when
//! its databases are opened again, and every hand-on is all there or not
//! at all (`runtime-model.md` section 3: *Every Ledger write counts only
//! once the database has it durably* and *Every hand-on is one atomic
//! write*; *What proves it*: a kill at each step, nothing lost).
//!
//! The kill is the operating system's — `TerminateProcess` on Windows,
//! `SIGKILL` elsewhere — while the child writes as fast as it can, so it
//! lands between writes and inside them alike. It proves what a process
//! dying proves: what was acknowledged had left the process. That it had
//! also reached the disk is the engine's synced write, which a machine
//! losing power would prove and this does not.

use std::time::Duration;

use xmip_persist::storage::{JourneyRecord, XmipStorage};

use super::{directory, hand_on, heard, journey, message, say, spawn, test_node};

/// How long a child is given to show it is working.
const STARTED: Duration = Duration::from_secs(60);

/// Writes a Journey after another, saying each once it is acknowledged.
pub fn write_until_killed(node: &dyn XmipStorage) {
    for number in 0..1_000_000 {
        let record = JourneyRecord {
            journey: journey(number),
            body: format!("written {number}").into_bytes(),
            facts: xmip_persist::storage::JourneyFacts::default(),
        };
        node.write_journey(&record).expect("written");
        say(&format!("written {number}"));
    }
}

/// Claims a Journey and hands it on, one after another, saying each.
pub fn hand_on_until_killed(node: &dyn XmipStorage) {
    let lease = Duration::from_secs(300);
    let holder = xmip_configure::fixture::test_cluster().node_scope(0);
    for number in 0..1_000_000 {
        let token = u128::from(number) + 1;
        let claim = node
            .claim(journey(number), &holder, token, lease)
            .expect("claimed")
            .expect("free");
        say(&format!("claimed {number}"));
        assert!(node.hand_on(&hand_on(number, claim)).expect("handed on"));
        say(&format!("handed {number}"));
    }
}

/// The last number a child acknowledged, once it has acknowledged
/// `enough`, and the child killed.
fn killed_after(what: &str, place: &std::path::Path, said: &str, enough: u64) -> u64 {
    let (mut child, lines) = spawn(what, place);
    let mut last = 0;
    while last < enough {
        last = heard(&lines, said, STARTED).parse().expect("a number");
    }
    child.kill().expect("killed");
    let _ = child.wait();
    // What it said before it died, all of it.
    while let Ok(line) = lines.recv_timeout(Duration::from_secs(1)) {
        if let Some(number) = line.strip_prefix(said) {
            last = number.trim().parse().expect("a number");
        }
    }
    last
}

#[test]
fn a_write_acknowledged_before_the_kill_is_there_after_it() {
    let place = directory("durable");
    let last = killed_after("write", &place, "written ", 200);
    let node = test_node(&place);
    for number in 0..=last {
        let read = node.read_journey(journey(number)).expect("read");
        let body = read.unwrap_or_else(|| panic!("acknowledged write {number} of {last} lost"));
        assert_eq!(body.body, format!("written {number}").into_bytes());
    }
    drop(node);
    let _ = std::fs::remove_dir_all(&place);
}

#[test]
fn a_hand_on_killed_at_any_moment_is_all_there_or_not_at_all() {
    let place = directory("atomic");
    let last = killed_after("hand-on", &place, "handed ", 200);
    let node = test_node(&place);
    let (mut whole, mut absent) = (0, 0);
    let other = xmip_configure::fixture::test_cluster().node_scope(1);
    for number in 0..last + 3 {
        let result = node.read_journey(journey(number)).expect("read");
        let messages: Vec<bool> = (0..3)
            .map(|part| {
                node.read_message(message(number, part))
                    .expect("read")
                    .is_some()
            })
            .collect();
        let next = node
            .read_journey(journey(number + 1_000_000))
            .expect("read");
        let free = node
            .claim(journey(number), &other, u128::MAX, Duration::ZERO)
            .expect("claimed")
            .is_some();
        if result.is_some() {
            assert!(
                messages.iter().all(|kept| *kept),
                "{number}: messages missing"
            );
            assert!(next.is_some(), "{number}: the next Journey missing");
            assert!(free, "{number}: the claim was not released with it");
            whole += 1;
        } else {
            assert!(
                messages.iter().all(|kept| !*kept),
                "{number}: half a hand-on"
            );
            assert!(next.is_none(), "{number}: half a hand-on");
            absent += 1;
        }
    }
    assert!(
        whole > last,
        "every hand-on acknowledged is there: {whole} of {last}"
    );
    assert!(
        absent >= 1,
        "the numbers past the kill are not there: {absent}"
    );
    drop(node);
    let _ = std::fs::remove_dir_all(&place);
}
