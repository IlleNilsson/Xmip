//! A node trusts a slice before it runs it, and keeps the last one that ran
//! (ADR-0031, amendment 2026-11-12), held end to end through the assembled
//! service: a correctly signed slice the node cannot start is refused at
//! its phase while the configuration that ran before keeps running and
//! stays recoverable, the trust pin stays, and replay protection is not
//! weakened — an older serial is still refused, even one above the
//! configuration that runs.

use xmip_configure::signed::{Pin, active_at, pin_at, split};
use xmip_observe::{Health, Publication};
use xmip_runtime::fixture::{unsigned, write_signed};

use super::*;

/// The file at `path`, whole.
fn kept(path: &Path) -> String {
    std::fs::read_to_string(path).expect("kept")
}

/// The serial the slice `file` was signed under.
fn serial(file: &str) -> u64 {
    split(file).expect("reads").1.expect("signed").serial
}

/// The node's pin.
fn pin(configuration: &Path) -> Pin {
    Pin::read(&kept(&pin_at(configuration))).expect("pinned")
}

/// Start the service at `configuration`, hear it accept work, deliver one
/// Message to `receive`, and stop it: received, and drained with exit 0.
fn ran(configuration: &Path, directory: &Path, receive: &str) {
    let mut child = spawned(configuration, directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        &format!("{} accepts work", node_scope()),
        Duration::from_secs(10),
    );
    deliver(receive, b"<order/>");
    stop(&child);
    let stopped = heard(&said, "stopped by the console", Duration::from_secs(5));
    assert!(exited(child, Duration::from_secs(5)).success());
    ending.0 = None;
    assert!(stopped.contains("received 1"), "{stopped}");
}

/// The node's record at `<node>/configuration`, as the publication it left
/// in `directory` says: a stopped node keeps it.
fn standing(directory: &Path) -> (Health, String) {
    let text = kept(&directory.join("data").join("snapshot.xmip"));
    let publication = Publication::read(&text).expect("reads");
    let scope = format!("{}/configuration", node_scope());
    let found = publication.records.into_iter().find(|r| r.scope == scope);
    let record = found.expect("its configuration standing is published");
    (record.health, record.evidence)
}

/// What `xmip-service` says asked `asked` of the node at `configuration`,
/// auditing in `directory`, and its exit code.
pub(super) fn asked(
    configuration: &Path,
    directory: &Path,
    asked: &[&str],
) -> (Option<i32>, String) {
    let output = Command::new(env!("CARGO_BIN_EXE_xmip-service"))
        .args(["--configuration", configuration.to_str().expect("UTF-8")])
        .args(asked)
        .env("XMIP_AUDIT_DIRECTORY", directory.join("audit"))
        .env("XMIP_PROCESS_DIRECTORY", directory.join("process"))
        .output()
        .expect("runs");
    let said = String::from_utf8_lossy(&output.stdout) + String::from_utf8_lossy(&output.stderr);
    (output.status.code(), said.into_owned())
}

/// What `xmip-service --activation` says of the slice at `configuration`,
/// and its exit code.
fn activation(configuration: &Path, directory: &Path) -> (Option<i32>, String) {
    asked(configuration, directory, &["--activation"])
}

/// ADR-0056, amendment 2026-11-23: a node is ready while it runs its slice
/// and its Xmip Storage stands Fine, as its publication says — what a
/// deployment waits for, `--within` its bound, before it restarts the next
/// node — and not before it has published, nor once it has stopped.
#[test]
fn a_node_is_ready_while_it_runs_its_slice_and_its_storage_stands_fine() {
    let directory = xmip_file::temporary::Folder::new("service-readiness");
    let receive = unheld().to_string();
    let configuration = written(&directory, &receive);
    let (code, said) = asked(&configuration, &directory, &["--readiness"]);
    assert_eq!(code, Some(2), "{said}");
    assert!(said.contains("has published nothing"), "{said}");

    let child = spawned(&configuration, &directory);
    let mut ending = Ending(Some(child.id()));
    let mut child = child;
    let said = lines(&mut child);
    heard(
        &said,
        &format!("{} accepts work", node_scope()),
        Duration::from_secs(10),
    );
    let (code, ready) = asked(
        &configuration,
        &directory,
        &["--readiness", "--within", "10"],
    );
    assert_eq!(code, Some(0), "{ready}");
    assert!(ready.contains("its own Storage node"), "{ready}");
    stop(&child);
    heard(&said, "stopped by the console", Duration::from_secs(5));
    assert!(exited(child, Duration::from_secs(5)).success());
    ending.0 = None;

    let (code, stopped) = asked(
        &configuration,
        &directory,
        &["--readiness", "--within", "1"],
    );
    assert_eq!(code, Some(2), "{stopped}");
    for words in [
        "REFUSED within 1 s",
        "the node is not ready",
        "stopped with the node",
    ] {
        assert!(stopped.contains(words), "{words}: {stopped}");
    }
}

#[test]
fn a_signed_slice_the_node_cannot_start_leaves_its_active_configuration_running_and_recoverable() {
    let directory = xmip_file::temporary::Folder::new("service-activation");
    let receive = unheld().to_string();

    // 1. The first start: the slice runs, and is pinned and active.
    let configuration = written(&directory, &receive);
    let first = kept(&configuration);
    ran(&configuration, &directory, &receive);
    assert_eq!(kept(&active_at(&configuration)), first);
    let pinned = pin(&configuration);
    let (s1, by) = (serial(&first), pinned.by.clone());
    assert_eq!(pinned.serial, s1);

    // 2. A runnable slice signed and kept aside, then the candidate signed
    // after it: correctly signed, and naming a transport no build links.
    let sound = unsigned(&configuration);
    write_signed(
        &configuration,
        &sound.replace("timeout = \"100ms\"", "timeout = \"150ms\""),
    );
    let older = kept(&configuration);
    write_signed(&configuration, &sound.replacen("tcp://", UNLINKED, 1));
    let s2 = serial(&kept(&configuration));
    assert!(s1 < serial(&older) && serial(&older) < s2);

    // 3. Deployed: the node is not refused; the first configuration's tcp
    // Receive Location takes what is sent, the candidate's is unlinked.
    ran(&configuration, &directory, &receive);
    let (health, said) = standing(&directory);
    assert_eq!(health, Health::Stressed, "{said}");
    for words in [
        "candidate refused",
        "refused at validate-startup",
        &format!("no transport for {UNLINKED}"),
        &format!("active configuration, serial {s1} of save"),
    ] {
        assert!(said.contains(words), "{words}: {said}");
    }
    let (code, asked) = activation(&configuration, &directory);
    assert_eq!(code, Some(2), "{asked}");
    assert!(
        asked.contains("is not what the node runs: candidate refused"),
        "{asked}"
    );

    // 4. The configuration that ran is retained, and the pin is untouched
    // but for the serial seen.
    assert_eq!(kept(&active_at(&configuration)), first);
    assert_eq!(
        (pin(&configuration).serial, pin(&configuration).by),
        (s2, by)
    );

    // 5. Replay protection holds: the slice kept aside is valid, runnable
    // and above the active one's serial, and below the serial seen.
    std::fs::write(&configuration, &older).expect("placed back");
    let seen = pin(&configuration);
    ran(&configuration, &directory, &receive);
    let (health, said) = standing(&directory);
    assert_eq!(health, Health::Stressed, "{said}");
    for words in [
        &format!("is not above {s2}"),
        "older, or replayed",
        &format!("active configuration, serial {s1} of save"),
    ] {
        assert!(said.contains(words), "{words}: {said}");
    }
    assert_eq!(kept(&active_at(&configuration)), first);
    assert_eq!(pin(&configuration), seen);

    // 6. Recovery forward, the pin never removed: signed again, it runs.
    write_signed(&configuration, &sound);
    let s3 = serial(&kept(&configuration));
    ran(&configuration, &directory, &receive);
    let (health, said) = standing(&directory);
    assert_eq!(health, Health::Fine, "{said}");
    assert!(
        said.starts_with(&format!("activated: serial {s3} of save")),
        "{said}"
    );
    assert!(
        said.contains(&format!("replacing serial {s1} of save")),
        "{said}"
    );
    let (code, asked) = activation(&configuration, &directory);
    assert_eq!(code, Some(0), "{asked}");
    assert_eq!(kept(&active_at(&configuration)), kept(&configuration));
    assert_eq!(pin(&configuration).serial, s3);

    let audit = kept(&directory.join("audit").join("audit.toml"));
    for words in [
        "action = \"configuration\"",
        "candidate refused",
        &format!("\"replaced\" = \"serial {s1} of save"),
    ] {
        assert!(audit.contains(words), "{words} in {audit}");
    }
}
