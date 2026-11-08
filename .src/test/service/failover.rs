//! Nodes reaching Xmip Storage over the wire, each `xmip-service` a process
//! of its own over loopback, through the same code as on machines of their
//! own: the test cluster's two Storage nodes, the first the primary and the
//! second its standby copying it; a receiving node taking files dropped in
//! a file Receive Location; a sending node writing each to a file Send
//! Location; neither keeping Xmip Storage itself (ADR-0056, amendments
//! 2026-10-20 and 2026-10-22). The primary is stopped while files are
//! dropped, and the standby is not promoted: with no witness, a primary
//! gone is waited for (ADR-0056, amendment 2026-11-08), so no file dropped
//! after the stop arrives until the primary is started again. Once it is,
//! every one listed answers, they settle, and every file dropped arrives,
//! once, whole; the time a file takes is measured on both sides.

use std::path::{Path, PathBuf};
use std::process::Child;
use std::time::{Duration, Instant};

use std::sync::mpsc::Receiver;

use super::{Ending, exited, heard, lines, spawned, stop, test_cluster, told, watched};

/// The files dropped before the primary stops, and as many after.
const HALF: usize = 20;

/// What bounds a file's way from its drop to its file sent, the primary's
/// return included: a bound on the test, never on Xmip.
const CARRY: Duration = Duration::from_secs(30);

/// The Application the receiving and the sending node share: one file
/// Receive Location, one file Send Port, every Message onward.
const APPLICATION: &str = r#"
[[xmip_applications]]
name = "Carried"

[[xmip_applications.receive_ports]]
name = "Carried"

[[xmip_applications.receive_locations]]
name = "In"
receive_port = "Carried"
depth = "light"

[[xmip_applications.send_ports]]
name = "Out"

[[xmip_applications.subscriptions]]
id = "onward"
destination = { send-port = "Out" }
filter = "xmip.transport.mechanism = 'circumstance'"
"#;

/// A path as a configuration names it.
fn named(path: &Path) -> String {
    path.display().to_string().replace('\\', "/")
}

/// The cluster's nodes declaring `role`, by name.
fn declaring(role: &str) -> Vec<String> {
    test_cluster()
        .nodes
        .iter()
        .filter(|node| node.roles.iter().any(|declared| declared == role))
        .map(|node| node.name.clone())
        .collect()
}

/// The configuration of `node`, declaring `roles`, in a folder of its own
/// beneath `directory`: reaching the Storage nodes at `addresses` with the
/// certificate `directory`'s `tls` holds, serving them at `served` where it
/// is one, and `bound` — its bindings of the Application.
fn configured(
    directory: &Path,
    (node, roles): (&str, &str),
    (addresses, served): (&[String], Option<&str>),
    bound: &str,
) -> PathBuf {
    let own = directory.join(node);
    std::fs::create_dir_all(&own).expect("a folder");
    let tls = named(&directory.join("tls"));
    let quoted: Vec<String> = addresses.iter().map(|at| format!("\"{at}\"")).collect();
    let listen_line = served
        .map(|at| format!("listen = \"{at}\"\n"))
        .unwrap_or_default();
    let local = format!("xmip-failover-{}-{node}", std::process::id());
    let text = format!(
        "roles = \"{roles}\"\n\n[service]\nname = \"xmip-{node}\"\ncluster_name = \"{cluster}\"\n\
         node_name = \"{node}\"\ndata = \"data\"\n\n\
         [tuning]\nstorage_silence = \"500ms\"\nsend_scan = \"50ms\"\nreceive_backoff = \"50ms\"\n\n\
         [storage]\nnodes = [{nodes}]\n{listen_line}certificate = \"{tls}/node.pem\"\n\
         key = \"{tls}/node.key\"\nanchors = \"{tls}/anchors.pem\"\n\
         {bound}{APPLICATION}\n[operate]\nlocal = \"{local}\"\n",
        cluster = test_cluster().name,
        nodes = quoted.join(", "),
    );
    let path = own.join(format!("{node}.xmip"));
    xmip_runtime::fixture::write_signed(&path, &text);
    path
}

/// A node running: its process, what ends it if the test does not, and the
/// lines it says.
type Running = (Child, Ending, Receiver<String>);

/// A node started from `configuration`, once it says it accepts work.
fn started(configuration: &Path, scope: &str) -> Running {
    let folder = configuration.parent().expect("its folder");
    let mut child = spawned(configuration, folder);
    let ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        &format!("{scope} accepts work"),
        Duration::from_secs(20),
    );
    (child, ending, said)
}

/// `count` files dropped into `drop` from `first` on, each written beside
/// and renamed in.
fn dropped(directory: &Path, drop: &Path, (first, count): (usize, usize)) {
    for number in first..first + count {
        let name = format!("order-{number}.edi");
        let beside = directory.join(format!("{name}.part"));
        std::fs::write(&beside, content(number)).expect("written");
        std::fs::rename(&beside, drop.join(&name)).expect("dropped");
    }
}

fn content(number: usize) -> Vec<u8> {
    format!("ISA*00*{number}*").repeat(64 + number).into_bytes()
}

/// The names of the files sent whole in `out`, sorted: none being written.
fn names(out: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(out)
        .map(|entries| {
            entries
                .filter_map(Result::ok)
                .map(|entry| entry.file_name().to_string_lossy().into_owned())
                .filter(|name| {
                    Path::new(name)
                        .extension()
                        .is_some_and(|extension| extension.eq_ignore_ascii_case("edi"))
                })
                .collect()
        })
        .unwrap_or_default();
    names.sort();
    names
}

/// The names in `out` once it holds `count` files, within the bound: told
/// by the file system each time it changes, never looking.
fn arrived(changed: &Receiver<()>, out: &Path, count: usize) -> Vec<String> {
    told(changed, Instant::now() + CARRY, || {
        names(out).len() >= count
    });
    names(out)
}

/// The certificate, key and anchors every node reaches Xmip Storage with,
/// written to `directory`'s `tls`.
fn certified(directory: &Path) {
    let authority = xmip_runtime::fixture::Authority::new();
    let (certificate, key, anchors) = authority.pem("node");
    std::fs::create_dir_all(directory.join("tls")).expect("a folder");
    for (file, pem) in [
        ("node.pem", certificate),
        ("node.key", key),
        ("anchors.pem", anchors),
    ] {
        std::fs::write(directory.join("tls").join(file), pem).expect("written");
    }
}

/// The scope `node` says it accepts work in.
fn scope(node: &str) -> String {
    format!("{}/node/{node}", test_cluster().scope())
}

/// The cluster's two Storage nodes started, each serving at its own of
/// `addresses`: the primary, with its configuration and the scope it says
/// it accepts work in, then its standby.
fn storage_started(
    directory: &Path,
    addresses: &[String],
) -> ((Running, PathBuf, String), Running) {
    let mut primary = None;
    let mut standby = None;
    for (place, node) in declaring("storage").iter().enumerate().take(2) {
        let path = configured(
            directory,
            (node, "storage"),
            (addresses, Some(&addresses[place])),
            "",
        );
        let running = started(&path, &scope(node));
        if place == 0 {
            primary = Some((running, path, scope(node)));
        } else {
            standby = Some(running);
        }
    }
    (primary.expect("the primary"), standby.expect("the standby"))
}

/// `node`'s binding of the Application's `kind` called `name` to `at`,
/// with `accept` after it.
fn binding(node: &str, kind: &str, name: &str, at: &Path, accept: &str) -> String {
    format!(
        "\n[[applications]]\nname = \"Carried\"\n\n[[applications.{kind}]]\n\
         name = \"{name}\"\nnode = \"{node}\"\naddress = \"{}\"\n{accept}",
        named(at)
    )
}

/// The receiving node taking files dropped in `drop`, and the sending node
/// writing each to `out`, started reaching Xmip Storage at `addresses`.
fn carriers_started(
    directory: &Path,
    (drop, out): (&Path, &Path),
    addresses: &[String],
) -> (Running, Running) {
    let (receiver, sender) = (
        declaring("receiving")[0].clone(),
        declaring("sending")[0].clone(),
    );
    let receiving = configured(
        directory,
        (&receiver, "receiving"),
        (addresses, None),
        &binding(
            &receiver,
            "receive_locations",
            "In",
            drop,
            "[applications.receive_locations.accept]\nmechanism = [\"circumstance\"]\n\
             transport = \"claimed\"\n",
        ),
    );
    let sending = configured(
        directory,
        (&sender, "sending"),
        (addresses, None),
        &binding(&sender, "send_ports", "Out", out, ""),
    );
    let receiving_node = started(&receiving, &scope(&receiver));
    let sending_node = started(&sending, &scope(&sender));
    (receiving_node, sending_node)
}

/// A node stopped by the console, once it has exited.
fn stopped((child, mut ending, said): Running) {
    stop(&child);
    heard(&said, "stopped by the console", Duration::from_secs(10));
    assert!(exited(child, Duration::from_secs(10)).success());
    ending.0 = None;
}

/// Every file dropped is in `out`, once, nothing beside it, and whole.
fn all_arrived_whole(arrived: &[String], out: &Path) {
    let expected: Vec<String> = {
        let mut names: Vec<String> = (0..2 * HALF).map(|n| format!("order-{n}.edi")).collect();
        names.sort();
        names
    };
    assert_eq!(arrived, expected, "every file once, nothing beside it");
    for number in 0..2 * HALF {
        let sent = std::fs::read(out.join(format!("order-{number}.edi"))).expect("arrived");
        assert_eq!(sent, content(number), "order-{number}.edi whole");
    }
}

#[test]
fn every_file_dropped_arrives_once_when_the_primary_storage_node_stops_mid_run_and_returns() {
    let directory =
        std::env::temp_dir().join(format!("xmip-service-failover-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    certified(&directory);
    let (drop, out) = (directory.join("in"), directory.join("out"));
    std::fs::create_dir_all(&drop).expect("the drop directory");
    std::fs::create_dir_all(&out).expect("the send directory");
    let addresses: Vec<String> = declaring("storage")
        .iter()
        .map(|_| xmip_net::fixture::unheld().to_string())
        .collect();
    let ((primary, primary_path, primary_scope), standby) = storage_started(&directory, &addresses);
    let (receiving, sending) = carriers_started(&directory, (&drop, &out), &addresses);

    let began = Instant::now();
    dropped(&directory, &drop, (0, HALF));
    let (changed, _watch) = watched(&out);
    let before = arrived(&changed, &out, HALF);
    assert_eq!(before.len(), HALF, "before the primary stops: {before:?}");
    let carried_before = began.elapsed();

    let stopping = Instant::now();
    dropped(&directory, &drop, (HALF, HALF / 2));
    stopped(primary);
    let primary_stopped = stopping.elapsed();
    let late = HALF + HALF / 2;
    dropped(&directory, &drop, (late, HALF - HALF / 2));

    // No witness: the standby is not promoted, so nothing dropped after the
    // stop is taken in while the primary is gone: six times its silence.
    std::thread::sleep(Duration::from_secs(3));
    let waiting = names(&out);
    assert!(
        (late..2 * HALF).all(|n| !waiting.contains(&format!("order-{n}.edi"))),
        "a file dropped after the primary stopped arrived without it: {waiting:?}"
    );

    let returning = Instant::now();
    let primary = started(&primary_path, &primary_scope);
    let after = arrived(&changed, &out, 2 * HALF);
    let settled = returning.elapsed();

    all_arrived_whole(&after, &out);
    println!(
        "carried {HALF} files through the primary in {carried_before:?}, and {HALF} more across \
         its stop, after {primary_stopped:?}, and its return, the rest arriving {settled:?} \
         after it was started again"
    );

    stopped(sending);
    stopped(receiving);
    stopped(standby);
    stopped(primary);
    let _ = std::fs::remove_dir_all(&directory);
}
