//! The getting-started node, assembled: one `xmip-service` on one computer,
//! its roles executing and storage, carries a file dropped in its drop
//! directory to a file of the same name in its send directory, whole, and
//! audits it (open problem 33, repaired 2026-10-20). Every gate is the
//! build's own: the file transport's arrival, the circumstance the node
//! infers where nothing was presented and its `circumstance` authenticator
//! the Location's `accept` chooses (the owner, 2026-10-19), the `location`
//! policy admitting at the Receive Location and at the Send Location the
//! node starts (the owner, 2026-10-19), a Subscription, and the file Send
//! Location writing under the name the file was received under in the
//! directory its address names (ADR-0024, amendment 2026-10-20).
//!
//! **Measured against the millisecond rule.** What Xmip does around the
//! payload is the round from the moment the node claims the dropped file —
//! its dropped name goes from the drop directory — to the moment the file
//! is whole in the send directory: read, the three gates, the Ledger
//! write, the route, the Journey, the send step and the sent file's write,
//! sync and rename. The payload's own work is measured beside it: the
//! dropped file opened and read, the sent file written, synced and renamed
//! as a send writes it, and the Ledger's durable copy of it — the payload
//! appended to a file kept open and synced, as the write-ahead log keeps
//! it; **what is left is Xmip's
//! own share, and it is held under a millisecond**, the fastest of five,
//! beside the machine's own wake for each hand-off between threads the
//! path makes (`xcore::latency::PlainWake`, measured round by round under
//! the same load; `CONTRIBUTING.md`, *Rust is here for one reason*), run
//! alone, in `xmip-service-measured` (`measured.rs`). How long a file
//! waits in the drop directory before it is claimed is printed apart: the
//! file system's change notification wakes the Location, which lists the
//! directory and claims the file by its turn and rename (ADR-0024,
//! amendment 2026-10-20), so it is held under ten milliseconds — never the
//! recovery sweep's second (`[tuning] receive_sweep`). The rounds are
//! printed as `xcore::latency` spreads them.

use std::path::Path;

use xmip_core::latency::{FIVE, PlainWake, spread};

use super::*;

/// How many files are carried, one after another.
const ROUNDS: usize = 2 * FIVE;

/// The most Xmip's own share of a carried file may take, the fastest of
/// five, beside the machine's own wakes: the millisecond rule.
const OWN: Duration = Duration::from_millis(1);

/// The hand-offs between threads a carried file makes: the claim to its
/// carrying thread, to the Storage node's writer and back, to the send
/// step and to its sending thread.
const HAND_OFFS: u32 = 5;

/// The most a dropped file may wait for its claim, the fastest of five:
/// a word from the file system and the claim's few steps there, never a
/// poll or the sweep.
const CLAIM: Duration = Duration::from_millis(10);

/// The longest any one file may take from its drop to its arrival: a
/// bound on the test, never on Xmip; what Xmip does is measured apart.
const CARRY: Duration = Duration::from_secs(10);

/// The getting-started node in `directory`: a file Receive Location over
/// `in`, accepting the circumstance; the Loopback Application's
/// Subscription onward; a file Send Port writing in `out`.
fn file_node(directory: &Path) -> std::path::PathBuf {
    std::fs::create_dir_all(directory).expect("a directory");
    let cluster = &test_cluster().name;
    let node = node_name();
    let path = |name: &str| {
        directory
            .join(name)
            .display()
            .to_string()
            .replace('\\', "/")
    };
    let text = format!(
        r#"roles = "executing, storage"

[service]
name = "xmip-{node}"
cluster_name = "{cluster}"
node_name = "{node}"
data = "data"

[[applications]]
name = "Loopback"

[[applications.receive_locations]]
name = "In"
node = "{node}"
address = "{drop}"
[applications.receive_locations.accept]
mechanism = ["circumstance"]
transport = "claimed"

[[applications.send_ports]]
name = "Out"
node = "{node}"
address = "{out}"
{APPLICATION}
[operate]
local = "{local}"
"#,
        drop = path("in"),
        out = path("out"),
        local = endpoint(directory),
    );
    let configuration = directory.join(format!("{node}.toml"));
    std::fs::write(&configuration, text).expect("writes");
    configuration
}

/// Whether `name` is still in `directory` under the name it was dropped
/// under.
fn lies(directory: &Path, name: &str) -> bool {
    directory.join(name).exists()
}

#[test]
fn a_file_dropped_in_arrives_whole_in_the_send_directory_under_its_name() {
    let _machine = alone();
    let directory =
        std::env::temp_dir().join(format!("xmip-service-carried-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let configuration = file_node(&directory);
    let (drop, out) = (directory.join("in"), directory.join("out"));
    std::fs::create_dir_all(&drop).expect("the drop directory");

    let mut child = spawned(&configuration, &directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        &format!("{} accepts work", node_scope()),
        Duration::from_secs(10),
    );

    // Told by the operating system when either directory changes, never
    // looking: the test's own reading costs a wake, not a processor.
    std::fs::create_dir_all(&out).expect("the send directory");
    let (in_changed, _in_watch) = watched(&drop);
    let (out_changed, _out_watch) = watched(&out);
    let (mut worked, mut waited, mut file) = (Vec::new(), Vec::new(), Vec::new());
    let (mut log, mut logged) = (kept_open(&directory.join("ledger.log")), Vec::new());
    let mut read = Vec::new();
    let (plain, mut woke) = (PlainWake::start(), Vec::new());
    for round in 0..ROUNDS {
        let name = format!("order-{round}.edi");
        let content = format!("ISA*00*{round}*").repeat(64 + round).into_bytes();
        // Written beside and renamed in, as a producer that means it to be
        // whole drops a file.
        let beside = directory.join(format!("{name}.part"));
        std::fs::write(&beside, &content).expect("written");
        let dropped = Instant::now();
        std::fs::rename(&beside, drop.join(&name)).expect("dropped");

        let deadline = dropped + CARRY;
        let target = out.join(&name);
        let claimed = told(&in_changed, deadline, || !lies(&drop, &name))
            .unwrap_or_else(|| panic!("{name} was never claimed"));
        let arrived = told(&out_changed, deadline, || target.exists())
            .unwrap_or_else(|| panic!("{name} never arrived in {out:?}"));
        assert_eq!(
            std::fs::read(&target).expect("arrived"),
            content,
            "{name} whole"
        );
        worked.push(arrived - claimed);
        waited.push(claimed - dropped);
        file.push(written_whole(&directory.join("beside"), &content));
        read.push(read_whole(&directory.join("beside").join("order.edi")));
        logged.push(appended(&mut log, &content));
        woke.push(plain.round().0);
    }
    std::mem::drop(log);
    let worked = spread("a claimed file to its file sent", worked);
    let waited = spread(
        "a dropped file to its claim, told by the file system",
        waited,
    );
    let file = spread("its file written, synced and renamed beside it", file);
    let logged = spread("its Ledger copy appended and synced beside it", logged);
    let read = spread("its dropped file opened and read beside it", read);
    let wake = spread("a plain channel's wake beside it", woke).fastest_of_five;

    stop(&child);
    let stopped = heard(&said, "stopped by the console", Duration::from_secs(5));
    assert!(exited(child, Duration::from_secs(5)).success());
    ending.0 = None;

    assert!(stopped.contains(&format!("received {ROUNDS}")), "{stopped}");
    let mut sent: Vec<String> = std::fs::read_dir(&out)
        .expect("the send directory")
        .map(|entry| {
            entry
                .expect("an entry")
                .file_name()
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    sent.sort();
    let mut expected: Vec<String> = (0..ROUNDS)
        .map(|round| format!("order-{round}.edi"))
        .collect();
    expected.sort();
    assert_eq!(
        sent, expected,
        "every file once, under its name, nothing beside it"
    );
    // The program's audit says what its node carried as it stopped; each
    // Message's own record is kept in its Storage node's audit database
    // (ADR-0070).
    let audit =
        std::fs::read_to_string(directory.join("audit").join("audit.toml")).expect("it audited");
    for each in ["received", "routed", "sent"] {
        let said = format!("\"{each}\" = \"{ROUNDS}\"");
        assert!(audit.contains(&said), "{said} in {audit}");
    }
    let load = read.fastest_of_five + file.fastest_of_five + logged.fastest_of_five;
    let own = worked.fastest_of_five.saturating_sub(load);
    println!(
        "carried {ROUNDS} files: {:?} fastest of five, of which the dropped file's read {:?}, the \
         sent file's own write, sync and rename {:?} and its Ledger copy {:?}: Xmip's own share \
         {own:?} ({:?} beyond the sent file alone); waiting for the claim {:?}",
        worked.fastest_of_five,
        read.fastest_of_five,
        file.fastest_of_five,
        logged.fastest_of_five,
        worked.fastest_of_five.saturating_sub(file.fastest_of_five),
        waited.fastest_of_five
    );
    let bound = OWN + wake * HAND_OFFS;
    assert!(
        own < bound,
        "Xmip's own share {own:?}, over {bound:?}: {OWN:?} and the machine's wake {wake:?} \
         for each of {HAND_OFFS} hand-offs"
    );
    assert!(
        waited.fastest_of_five < CLAIM,
        "a dropped file waited {:?} for its claim",
        waited.fastest_of_five
    );
    let _ = std::fs::remove_dir_all(&directory);
}

/// How long the file at `path` takes to open and read whole: the load the
/// dropped file's own read carries, measured beside Xmip's work.
fn read_whole(path: &Path) -> Duration {
    let began = Instant::now();
    let read = std::fs::read(path).expect("read");
    let took = began.elapsed();
    assert!(!read.is_empty(), "read whole");
    took
}

/// A file kept open to append to, as the Ledger's write-ahead log is.
fn kept_open(path: &Path) -> std::fs::File {
    std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .expect("opened")
}

/// How long `content` takes to append to `log` and sync: the Ledger's
/// durable copy of the payload, the load its write carries, measured
/// beside Xmip's work.
fn appended(log: &mut std::fs::File, content: &[u8]) -> Duration {
    use std::io::Write;
    let began = Instant::now();
    log.write_all(content).expect("appended");
    log.sync_data().expect("synced");
    began.elapsed()
}

/// How long `content` takes to write as a file send writes it — beside,
/// synced, renamed into place — in `directory`: the load the send's own
/// file carries, measured beside Xmip's work.
fn written_whole(directory: &Path, content: &[u8]) -> Duration {
    use std::io::Write;
    std::fs::create_dir_all(directory).expect("a directory");
    let (beside, target) = (directory.join("order.part"), directory.join("order.edi"));
    let began = Instant::now();
    let mut written = std::fs::File::create(&beside).expect("created");
    written.write_all(content).expect("written");
    written.sync_all().expect("synced");
    drop(written);
    std::fs::rename(&beside, &target).expect("renamed");
    began.elapsed()
}
