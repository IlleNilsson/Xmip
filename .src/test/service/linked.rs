//! Every transport this build links carries a file through the node to its
//! own far end (the owner, 2026-11-24: *go through each item and sort it or
//! ask me*). One node, its own Storage node: a file Receive Location over a
//! drop folder, accepting the circumstance, and a Send Port for each linked
//! transport (`far_ends.rs`), each with a Subscription taking every Message
//! the node publishes, so one file dropped in is sent over every transport
//! at once, and each far end takes it whole. A far end that hands what it
//! took only once its connection is let go is joined after the node stops:
//! a node keeps its connections in its pool while it runs.
//!
//! A POP3 Location only collects, so it is proven receiving: the node's
//! Receive Location collects a maildrop this test serves, and the node
//! carries the mail to a file Send Port.

use std::fmt::Write as _;
use std::path::Path;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use super::far_ends::{self, BOUND, Standing};
use super::folder::{dropped, named, quoted};
use super::{Ending, exited, heard, lines, spawned, stop, test_cluster};
#[cfg(feature = "transport-pop3")]
use super::{told, watched};

/// What every far end takes: one XML document, short and plain, as every
/// linked protocol carries it whole — inside an MLLP block, a Peppol
/// Standard Business Document, a Modbus write, an IEC 104 ASDU.
const DOCUMENT: &str = "<probe><n>1</n>round-trip</probe>";

/// The node: `inbox` received from, and each of `standing` a Send Port with
/// a Subscription of its own taking every Message.
fn configuration(directory: &Path, inbox: &Path, standing: &[Standing]) -> String {
    let (cluster, node) = (&test_cluster().name, &test_cluster().node(0).name);
    let mut ports = String::new();
    let mut declared = String::new();
    for one in standing {
        let name = quoted(one.name);
        let (node, address) = (quoted(node), quoted(&one.address));
        let written = writeln!(
            ports,
            "\n[[applications.send_ports]]\nname = {name}\nnode = {node}\naddress = {address}"
        );
        written.expect("a String takes it");
        if !one.settings.is_empty() {
            ports.push_str("[applications.send_ports.settings]\n");
        }
        for (key, value) in &one.settings {
            writeln!(ports, "{key} = {value}").expect("a String takes it");
        }
        let written = writeln!(
            declared,
            "\n[[xmip_applications.send_ports]]\nname = {name}\n\n\
             [[xmip_applications.subscriptions]]\nid = {name}\n\
             destination = {{ send-port = {name} }}\n\
             filter = \"xmip.transport.mechanism = 'circumstance'\""
        );
        written.expect("a String takes it");
    }
    format!(
        "roles = \"executing, storage\"\n\n[service]\nname = \"xmip-{node}\"\n\
         cluster_name = \"{cluster}\"\nnode_name = \"{node}\"\n\n\
         [tuning]\nsend_scan = \"50ms\"\nreceive_backoff = \"50ms\"\n\n\
         [[applications]]\nname = \"Linked\"\n\n\
         [[applications.receive_locations]]\nname = \"In\"\nnode = {}\naddress = {}\n\
         [applications.receive_locations.accept]\nmechanism = [\"circumstance\"]\n\
         transport = \"claimed\"\n{ports}\n\
         [[xmip_applications]]\nname = \"Linked\"\n\n\
         [[xmip_applications.receive_ports]]\nname = \"Linked\"\n\n\
         [[xmip_applications.receive_locations]]\nname = \"In\"\nreceive_port = \"Linked\"\n\
         depth = \"light\"\n{declared}\n[operate]\nlocal = {}\n",
        quoted(node),
        quoted(&named(inbox)),
        quoted(&super::endpoint(directory)),
    )
}

/// The node configured in `directory`, started, once it accepts work.
fn started(directory: &Path, text: &str) -> (std::process::Child, Ending, mpsc::Receiver<String>) {
    let path = xmip_runtime::fixture::configuration_folder(directory).join("node.xmip");
    xmip_runtime::fixture::write_signed(&path, text);
    let mut child = spawned(&path, directory);
    let ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        &format!("{} accepts work", test_cluster().node_scope(0)),
        Duration::from_secs(20),
    );
    (child, ending, said)
}

/// What `name`'s far end took, or why it took nothing whole.
fn judged(name: &str, taken: xmip_transport::Result<xmip_transport::Taken>) -> Option<String> {
    match taken {
        Ok(taken) if taken.bytes == DOCUMENT.as_bytes() => None,
        Ok(taken) => Some(format!(
            "{name}: took {:?}",
            String::from_utf8_lossy(&taken.bytes)
        )),
        Err(failed) => Some(format!("{name}: {failed}")),
    }
}

#[test]
fn a_file_dropped_in_is_sent_over_every_linked_transport_to_its_own_far_end() {
    let directory = xmip_file::temporary::Folder::new("service-linked");
    let inbox = directory.join("in");
    std::fs::create_dir_all(&inbox).expect("a drop folder");
    let standing = far_ends::every(&directory);
    let (child, mut ending, said) =
        started(&directory, &configuration(&directory, &inbox, &standing));

    let (took, taking) = mpsc::channel();
    let (mut first, mut last) = (Vec::new(), Vec::new());
    for one in standing {
        if one.at_close { &mut last } else { &mut first }.push(one.name);
        let took = took.clone();
        std::thread::spawn(move || {
            let _ = took.send((one.name, one.far.take_one()));
        });
    }
    dropped(&directory, &inbox, "probe.xml", DOCUMENT);
    let mut failed = Vec::new();
    let deadline = Instant::now() + BOUND + Duration::from_secs(5);
    let heard_from = |waited: &mut Vec<&str>, failed: &mut Vec<String>| {
        while !waited.is_empty() {
            let left = deadline.saturating_duration_since(Instant::now());
            let Ok((name, taken)) = taking.recv_timeout(left) else {
                failed.extend(waited.drain(..).map(|name| format!("{name}: nothing")));
                return;
            };
            waited.retain(|waiting| *waiting != name);
            failed.extend(judged(name, taken));
        }
    };
    heard_from(&mut first, &mut failed);
    stop(&child);
    heard_from(&mut last, &mut failed);
    heard(&said, "stopped by the console", Duration::from_secs(10));
    assert!(exited(child, Duration::from_secs(10)).success());
    ending.0 = None;
    assert!(
        failed.is_empty(),
        "not carried whole:\n{}",
        failed.join("\n")
    );
}

/// A POP3 Receive Location collects the one mail a maildrop this test
/// serves holds, and the node carries it to a file Send Port, whole.
#[cfg(feature = "transport-pop3")]
#[test]
fn a_pop3_receive_location_collects_a_maildrop_through_the_node() {
    let directory = xmip_file::temporary::Folder::new("service-pop3");
    let out = directory.join("out");
    std::fs::create_dir_all(&out).expect("a send folder");
    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("a maildrop's port");
    let at = listener.local_addr().expect("its address").to_string();
    let maildrop = std::thread::spawn(move || {
        xmip_transport_pop3::Session::accept(&listener, vec![DOCUMENT.into()], Some(BOUND))
            .and_then(xmip_transport_pop3::Session::serve)
    });
    let (cluster, node) = (&test_cluster().name, &test_cluster().node(0).name);
    let text = format!(
        "roles = \"executing, storage\"\n\n[service]\nname = \"xmip-{node}\"\n\
         cluster_name = \"{cluster}\"\nnode_name = \"{node}\"\n\n\
         [[applications]]\nname = \"Mail\"\n\n\
         [[applications.receive_locations]]\nname = \"In\"\nnode = {}\naddress = {}\n\
         [applications.receive_locations.settings]\nuser = \"probe\"\n\
         [applications.receive_locations.accept]\nmechanism = [\"circumstance\"]\n\
         transport = \"claimed\"\n\n\
         [[applications.send_ports]]\nname = \"Out\"\nnode = {}\naddress = {}\n\n\
         [[xmip_applications]]\nname = \"Mail\"\n\n\
         [[xmip_applications.receive_ports]]\nname = \"Mail\"\n\n\
         [[xmip_applications.receive_locations]]\nname = \"In\"\nreceive_port = \"Mail\"\n\
         depth = \"light\"\n\n[[xmip_applications.send_ports]]\nname = \"Out\"\n\n\
         [[xmip_applications.subscriptions]]\nid = \"onward\"\n\
         destination = {{ send-port = \"Out\" }}\n\
         filter = \"xmip.transport.mechanism = 'circumstance'\"\n\n\
         [operate]\nlocal = {}\n",
        quoted(node),
        quoted(&format!("pop3://{at}")),
        quoted(node),
        quoted(&named(&out)),
        quoted(&super::endpoint(&directory)),
    );
    let (child, mut ending, said) = started(&directory, &text);
    let (changed, _watch) = watched(&out);
    let sent = || {
        std::fs::read_dir(&out).map_or_default(|entries| {
            entries
                .filter_map(Result::ok)
                .filter(|entry| !entry.file_name().to_string_lossy().contains(".xmip-"))
                .filter_map(|entry| std::fs::read(entry.path()).ok())
                .collect::<Vec<_>>()
        })
    };
    told(&changed, Instant::now() + BOUND, || !sent().is_empty());

    assert_eq!(sent(), [DOCUMENT.as_bytes()], "the mail, whole");
    assert!(maildrop.join().expect("the maildrop").is_ok(), "collected");
    stop(&child);
    heard(&said, "stopped by the console", Duration::from_secs(10));
    assert!(exited(child, Duration::from_secs(10)).success());
    ending.0 = None;
}
