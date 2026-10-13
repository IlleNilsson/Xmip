//! A node configured with `[operate]` is reached on its operate listener as
//! a surface on another machine reaches it (ADR-0067; ADR-0014, amendment
//! 2026-10-12): over gRPC inside Xmip's mutual TLS, with certificates one
//! test authority issued; its publication read, and a pause of its
//! Subscription taken as the certificate's subject and shown paused in the
//! next publication.

use xmip_observe::{PauseState, Publication};
use xmip_runtime::fixture::Authority;
use xmip_runtime::plane::{Outcome, Remote};

use super::*;

#[test]
fn a_node_is_read_and_acted_on_over_its_operate_listener() {
    let directory =
        std::env::temp_dir().join(format!("xmip-service-operate-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let receive = free_address();
    let configuration = written(&directory, &receive);
    let authority = Authority::new();
    let (certificate, key, anchors) = authority.pem("node");
    for (name, text) in [
        ("node.pem", &certificate),
        ("node.key", &key),
        ("anchor.pem", &anchors),
    ] {
        std::fs::write(directory.join(name), text).expect("writes");
    }
    let listen = free_address();
    let text = format!(
        "{}\n[operate]\nlisten = \"{listen}\"\ncertificate = \"node.pem\"\nkey = \"node.key\"\n\
         anchors = \"anchor.pem\"\nrole = \"operator\"\n",
        std::fs::read_to_string(&configuration).expect("reads")
    );
    std::fs::write(&configuration, text).expect("writes");

    let mut child = spawned(&configuration, &directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        &format!("is operated at {listen}"),
        Duration::from_secs(10),
    );

    let surface = Remote::open(&listen, &authority.identity("surface")).expect("a remote");
    let (_, published) = surface.publication().expect("the node answers");
    let read = Publication::read(&published).expect("a publication");
    assert_eq!(read.node, node_scope());

    let (outcome, sentence) = surface
        .act(&node_scope(), "subscription", "onward", "pause")
        .expect("the node answers");
    assert_eq!(outcome, Outcome::Taken, "{sentence}");
    let deadline = Instant::now() + Duration::from_secs(5);
    let mut state = surface.state();
    loop {
        let (_, text) = surface.publication().expect("the node answers");
        let paused = Publication::read(&text)
            .expect("a publication")
            .subscriptions
            .iter()
            .any(|subscription| {
                subscription.name == "onward" && subscription.state == PauseState::Paused
            });
        if paused {
            break;
        }
        assert!(Instant::now() < deadline, "never shown paused");
        state = surface.wait(state.told, Duration::from_secs(1));
    }

    stop(&child);
    assert!(exited(child, Duration::from_secs(10)).success());
    ending.0 = None;
    let _ = std::fs::remove_dir_all(&directory);
}

/// The same node on its own machine (ADR-0014, amendment 2026-10-13): on
/// its local endpoint, no certificate, the pause taken as the operating
/// system user this test runs as.
#[test]
fn a_node_is_read_and_acted_on_over_its_local_endpoint() {
    let directory = std::env::temp_dir().join(format!("xmip-service-local-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let receive = free_address();
    let configuration = written(&directory, &receive);
    let endpoint = format!("xmip-service-local-{}", std::process::id());
    let text = format!(
        "{}\n[operate]\nlocal = \"{endpoint}\"\nrole = \"operator\"\n",
        std::fs::read_to_string(&configuration).expect("reads")
    );
    std::fs::write(&configuration, text).expect("writes");

    let mut child = spawned(&configuration, &directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(&said, "is operated at", Duration::from_secs(10));

    let surface = Remote::local(&endpoint).expect("a local surface");
    // The listener answers before the node's first publication is posted:
    // the follow says when it is.
    let mut state = surface.wait(0, Duration::from_secs(5));
    let deadline = Instant::now() + Duration::from_secs(5);
    while state.revision == 0 && Instant::now() < deadline {
        state = surface.wait(state.told, Duration::from_secs(1));
    }
    let (_, published) = surface.publication().expect("the node answers");
    let read = Publication::read(&published).expect("a publication");
    assert_eq!(read.node, node_scope());
    let (outcome, sentence) = surface
        .act(&node_scope(), "subscription", "onward", "pause")
        .expect("the node answers");
    assert_eq!(outcome, Outcome::Taken, "{sentence}");

    drop(surface);
    stop(&child);
    assert!(exited(child, Duration::from_secs(10)).success());
    ending.0 = None;
    let _ = std::fs::remove_dir_all(&directory);
}
