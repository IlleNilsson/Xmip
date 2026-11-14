//! An operator's act asked at the door of the node declaring the
//! operational role, written to Xmip Storage and taken by the node it is
//! asked of (ADR-0014, amendment 2026-11-13): three `xmip-service`
//! processes over loopback — the test cluster's first Storage node, its
//! first receiving node and the node declaring the operational and
//! monitoring roles, the two reaching Xmip Storage over the wire, as on
//! machines of their own. A pause of the receiving node's Subscription
//! asked at the operational node's local endpoint is taken by the
//! receiving node and audited at both; with the receiving node stopped, a
//! resume is answered asked, and the receiving node takes it as it starts
//! again. Which node is which is read from the roles each declares, never
//! from a name.

use std::path::Path;
use std::time::{Duration, Instant};

use xmip_observe::{Act, PauseState, Publication};
use xmip_runtime::plane::{Outcome, Remote};

use super::failover::{
    Running, binding, certified, configured, declaring, local_of, scope, started, stopped,
};
use super::{operated, operator};

/// What `node` audited, as its audit file holds it.
fn audited(directory: &Path, node: &str) -> String {
    let file = directory.join(node).join("audit").join("audit.toml");
    std::fs::read_to_string(file).unwrap_or_default()
}

/// The receiving node's Subscription `onward` as its last publication says,
/// once `holds` says it holds, within a bound.
fn onward_until(directory: &Path, node: &str, holds: impl Fn(PauseState) -> bool) -> bool {
    let snapshot = directory.join(node).join("data").join("snapshot.xmip");
    let deadline = Instant::now() + Duration::from_secs(10);
    while Instant::now() < deadline {
        let read = std::fs::read_to_string(&snapshot)
            .ok()
            .and_then(|text| Publication::read(&text).ok());
        let state = read.and_then(|publication| {
            publication
                .subscriptions
                .into_iter()
                .find(|subscription| subscription.name == "onward")
                .map(|subscription| subscription.state)
        });
        if state.is_some_and(&holds) {
            return true;
        }
        std::thread::yield_now();
    }
    false
}

/// The receiving node configured to take files dropped in `drop`, listing
/// this test's account as an Operator.
fn receiving(directory: &Path, addresses: &[String], drop: &Path) -> (String, std::path::PathBuf) {
    let node = declaring("receiving")[0].clone();
    let accept = "[applications.receive_locations.accept]\nmechanism = [\"circumstance\"]\ntransport = \"claimed\"\n";
    let bound = binding(&node, "receive_locations", "In", drop, accept);
    let path = configured(directory, (&node, "receiving"), (addresses, None), &bound);
    operated(&path);
    (node, path)
}

#[test]
fn an_act_asked_at_the_operational_door_is_taken_by_its_node_and_asked_while_it_is_down() {
    let directory = std::env::temp_dir().join(format!("xmip-service-door-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    certified(&directory);
    let dropped_in = directory.join("in");
    std::fs::create_dir_all(&dropped_in).expect("the drop directory");
    let address = xmip_net::fixture::unheld().to_string();
    let addresses = vec![address.clone()];

    let storage_node = declaring("storage")[0].clone();
    let storage_path = configured(
        &directory,
        (&storage_node, "storage"),
        (&addresses, Some(&address)),
        "",
    );
    let storage: Running = started(&storage_path, &scope(&storage_node));
    let (receiver, receiving_path) = receiving(&directory, &addresses, &dropped_in);
    let receiving_node = started(&receiving_path, &scope(&receiver));
    let door_node = declaring("operational")[0].clone();
    let door_path = configured(
        &directory,
        (&door_node, "operational, monitoring"),
        (&addresses, None),
        "",
    );
    operated(&door_path);
    let door = started(&door_path, &scope(&door_node));

    let surface =
        Remote::local(&local_of(&directory, &door_node), Duration::ZERO).expect("a surface");
    let (outcome, said) = surface
        .act(0, &scope(&receiver), ("subscription", "onward", "pause"))
        .expect("the door answers");
    assert_eq!(outcome, Outcome::Taken, "{said}");
    assert!(
        said.contains(&format!("paused by {}", operator())),
        "{said}"
    );
    assert!(onward_until(&directory, &receiver, |state| state == PauseState::Paused));
    // Admitted at the door, taken at the node, each in its own audit.
    let asked = format!("asked at {}", scope(&door_node));
    assert!(
        audited(&directory, &receiver).contains(&asked),
        "taken where asked"
    );
    assert!(
        audited(&directory, &door_node).contains("asked to pause"),
        "admitted"
    );

    // Its node stopped: asked, never lost, and taken as it starts again.
    stopped(receiving_node);
    let (outcome, said) = surface
        .act(
            0,
            &scope(&receiver),
            ("subscription", "onward", Act::Resume.word()),
        )
        .expect("the door answers");
    assert_eq!(outcome, Outcome::Asked, "{said}");
    assert!(said.contains("not taken yet"), "{said}");
    let receiving_node = started(&receiving_path, &scope(&receiver));
    assert!(
        onward_until(&directory, &receiver, |state| state == PauseState::Active),
        "taken as it started again"
    );

    drop(surface);
    stopped(door);
    stopped(receiving_node);
    stopped(storage);
    let _ = std::fs::remove_dir_all(&directory);
}
