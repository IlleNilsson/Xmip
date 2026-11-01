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
//! payload is what the node's threads run for each file from the moment
//! its transport hands it to the node to the moment the file is whole in
//! the send directory: the three gates, the Ledger write, the route, the
//! Journey, the send step. The node counts that processor time for each
//! file, apart from the payload's own I/O — the dropped file read, the
//! Ledger's append and its sync, the sent file written, synced and renamed
//! (`xcore::spent`; the owner, 2026-11-01); **that is Xmip's own share, and
//! it is held under a millisecond**, the fastest of five as the node reports
//! it in its stop record (`Outcomes::own_share`; `CONTRIBUTING.md`, *Rust is
//! here for one reason*), built optimized and run alone, in
//! `xmip-service-measured` (`measured.rs`). A thread waiting for a wake
//! runs nothing, so no wake is counted; the file's time end to end is
//! printed beside it. How long a file
//! waits in the drop directory before it is claimed is printed apart: the
//! file system's change notification wakes the Location, which lists the
//! directory and claims the file by its turn and rename (ADR-0024,
//! amendment 2026-10-20), so it is held under ten milliseconds — never the
//! recovery sweep's second (`[tuning] receive_sweep`). The rounds are
//! printed as `xcore::latency` spreads them.

use std::path::Path;

use xmip_core::fastest::FIVE;
use xmip_core::latency::spread;

use super::*;

/// How many files are carried, one after another.
const ROUNDS: usize = 2 * FIVE;

/// The most Xmip's own share of a carried file may take, the fastest of
/// five: the millisecond rule.
const OWN: Duration = Duration::from_millis(1);

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
    let (mut worked, mut waited) = (Vec::new(), Vec::new());
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
    }
    let worked = spread("a claimed file to its file sent, for information", worked);
    let waited = spread(
        "a dropped file to its claim, told by the file system",
        waited,
    );

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
    let own = own_share(&audit);
    println!(
        "carried {ROUNDS} files: {:?} fastest of five, Xmip's own share {own:?} as the node \
         measured it; waiting for the claim {:?}",
        worked.fastest_of_five, waited.fastest_of_five
    );
    assert!(own < OWN, "Xmip's own share {own:?}, over {OWN:?}");
    assert!(
        waited.fastest_of_five < CLAIM,
        "a dropped file waited {:?} for its claim",
        waited.fastest_of_five
    );
    let _ = std::fs::remove_dir_all(&directory);
}

/// Xmip's own share of a carried file's time, the fastest of five, as the
/// node measured it and its stop record in `audit` says
/// (`xmip_runtime::outcome::Outcomes::own_share`).
fn own_share(audit: &str) -> Duration {
    let said = "\"own_share_ns\" = \"";
    let (_, after) = audit
        .split_once(said)
        .unwrap_or_else(|| panic!("the node measured its own share: {audit}"));
    let nanos = after.split('"').next().expect("a value");
    Duration::from_nanos(nanos.parse().expect("nanoseconds"))
}
