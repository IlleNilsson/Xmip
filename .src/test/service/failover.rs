//! Nodes reaching Xmip Storage over the wire, each `xmip-service` a process
//! of its own over loopback, through the same code as on machines of their
//! own: the test cluster's two Storage nodes, the first the primary and the
//! second its standby copying it; a receiving node taking files dropped in
//! a file Receive Location; a sending node writing each to a file Send
//! Location; neither keeping Xmip Storage itself (ADR-0056, amendments
//! 2026-10-20 and 2026-10-22). The primary is stopped while files are
//! dropped, and the standby is promoted: every file dropped arrives, once,
//! whole, and the time a file takes from its claim to its file sent is
//! measured on both sides of the failover.

use std::path::{Path, PathBuf};
use std::process::Child;
use std::time::{Duration, Instant};

use std::sync::mpsc::Receiver;

use super::{Ending, exited, heard, lines, spawned, stop, test_cluster, told, watched};

/// The files dropped before the primary stops, and as many after.
const HALF: usize = 20;

/// What bounds a file's way from its drop to its file sent, failover
/// included: a bound on the test, never on Xmip.
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
/// beneath `directory`: reaching the Storage nodes `listed` with the
/// certificate `directory`'s `tls` holds, serving them at `listen` where it
/// is one, and `bound` — its bindings of the Application.
fn configured(
    directory: &Path,
    (node, roles): (&str, &str),
    (listed, listen): (&[String], Option<&str>),
    bound: &str,
) -> PathBuf {
    let own = directory.join(node);
    std::fs::create_dir_all(&own).expect("a folder");
    let tls = named(&directory.join("tls"));
    let nodes: Vec<String> = listed.iter().map(|at| format!("\"{at}\"")).collect();
    let listen = listen
        .map(|at| format!("listen = \"{at}\"\n"))
        .unwrap_or_default();
    let text = format!(
        "roles = \"{roles}\"\n\n[service]\nname = \"xmip-{node}\"\ncluster_name = \"{cluster}\"\n\
         node_name = \"{node}\"\ndata = \"data\"\n\n\
         [tuning]\nstorage_silence = \"500ms\"\nsend_scan = \"50ms\"\nreceive_backoff = \"50ms\"\n\n\
         [storage]\nnodes = [{nodes}]\n{listen}certificate = \"{tls}/node.pem\"\n\
         key = \"{tls}/node.key\"\nanchors = \"{tls}/anchors.pem\"\n\
         {bound}{APPLICATION}\n[operate]\nlocal = \"{local}\"\n",
        cluster = test_cluster().name,
        nodes = nodes.join(", "),
        local = format!("xmip-failover-{}-{node}", std::process::id()),
    );
    let path = own.join(format!("{node}.toml"));
    std::fs::write(&path, text).expect("written");
    path
}

/// A node started from `configuration`, once it says it accepts work.
fn started(
    configuration: &Path,
    scope: &str,
) -> (Child, Ending, std::sync::mpsc::Receiver<String>) {
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
                .filter(|name| name.ends_with(".edi"))
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

#[test]
fn every_file_dropped_arrives_once_when_the_primary_storage_node_stops_mid_run() {
    let _machine = super::sharing();
    let directory =
        std::env::temp_dir().join(format!("xmip-service-failover-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
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
    let (drop, out) = (directory.join("in"), directory.join("out"));
    std::fs::create_dir_all(&drop).expect("the drop directory");
    std::fs::create_dir_all(&out).expect("the send directory");
    let storage = declaring("storage");
    let listed: Vec<String> = storage
        .iter()
        .map(|_| xmip_net::fixture::unheld().to_string())
        .collect();
    let (receiver, sender) = (
        declaring("receiving")[0].clone(),
        declaring("sending")[0].clone(),
    );
    let cluster = test_cluster().scope();
    let scope = |node: &str| format!("{cluster}/node/{node}");

    let mut primary = None;
    let mut standby = None;
    for (place, node) in storage.iter().enumerate().take(2) {
        let path = configured(
            &directory,
            (node, "storage"),
            (&listed, Some(&listed[place])),
            "",
        );
        let running = started(&path, &scope(node));
        if place == 0 {
            primary = Some(running);
        } else {
            standby = Some(running);
        }
    }
    let binding = |node: &str, kind: &str, name: &str, at: &Path, accept: &str| {
        format!(
            "\n[[applications]]\nname = \"Carried\"\n\n[[applications.{kind}]]\n\
             name = \"{name}\"\nnode = \"{node}\"\naddress = \"{}\"\n{accept}",
            named(at)
        )
    };
    let receiving = configured(
        &directory,
        (&receiver, "receiving"),
        (&listed, None),
        &binding(
            &receiver,
            "receive_locations",
            "In",
            &drop,
            "[applications.receive_locations.accept]\nmechanism = [\"circumstance\"]\n",
        ),
    );
    let sending = configured(
        &directory,
        (&sender, "sending"),
        (&listed, None),
        &binding(&sender, "send_ports", "Out", &out, ""),
    );
    let (r_child, mut r_ending, r_said) = started(&receiving, &scope(&receiver));
    let (s_child, mut s_ending, s_said) = started(&sending, &scope(&sender));

    let began = Instant::now();
    dropped(&directory, &drop, (0, HALF));
    let (changed, _watch) = watched(&out);
    let before = arrived(&changed, &out, HALF);
    assert_eq!(before.len(), HALF, "before the failover: {before:?}");
    let carried_before = began.elapsed();

    let (p_child, mut p_ending, p_said) = primary.take().expect("the primary");
    let stopping = Instant::now();
    dropped(&directory, &drop, (HALF, HALF / 2));
    stop(&p_child);
    heard(&p_said, "stopped by the console", Duration::from_secs(10));
    assert!(exited(p_child, Duration::from_secs(10)).success());
    p_ending.0 = None;
    let primary_stopped = stopping.elapsed();
    dropped(&directory, &drop, (HALF + HALF / 2, HALF - HALF / 2));
    let after = arrived(&changed, &out, 2 * HALF);
    let failed_over = stopping.elapsed();

    let expected: Vec<String> = {
        let mut names: Vec<String> = (0..2 * HALF).map(|n| format!("order-{n}.edi")).collect();
        names.sort();
        names
    };
    assert_eq!(after, expected, "every file once, nothing beside it");
    for number in 0..2 * HALF {
        let sent = std::fs::read(out.join(format!("order-{number}.edi"))).expect("arrived");
        assert_eq!(sent, content(number), "order-{number}.edi whole");
    }
    println!(
        "carried {HALF} files through the primary in {carried_before:?}, and {HALF} more across \
         its stop and the standby's promotion in {failed_over:?}, the primary stopped after \
         {primary_stopped:?}"
    );

    for (child, ending, said) in [
        (s_child, &mut s_ending, s_said),
        (r_child, &mut r_ending, r_said),
    ] {
        stop(&child);
        heard(&said, "stopped by the console", Duration::from_secs(10));
        assert!(exited(child, Duration::from_secs(10)).success());
        ending.0 = None;
    }
    let (d_child, mut d_ending, d_said) = standby.take().expect("the standby");
    stop(&d_child);
    heard(&d_said, "stopped by the console", Duration::from_secs(10));
    assert!(exited(d_child, Duration::from_secs(10)).success());
    d_ending.0 = None;
    let _ = std::fs::remove_dir_all(&directory);
}
