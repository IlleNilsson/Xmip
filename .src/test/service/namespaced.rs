//! Every transport this build links whose far end is on a link of the
//! kernel's — a CAN interface, an Ethernet interface's raw socket — carries a
//! file through the node to it, as `linked.rs` carries the rest (the owner,
//! 2026-11-25: *just do your best for now*). Making a virtual CAN interface
//! or a veth pair, and opening a raw socket on one, asks for `CAP_NET_ADMIN`
//! and `CAP_NET_RAW`; a user and network namespace of the test's own grants
//! both over that namespace alone, to the account's own user, its root
//! there. So the test runs itself again inside one (`unshare`), brings the
//! loopback interface up, makes every interface the far ends stand on
//! (`far_ends/kernel.rs`) with iproute2's `ip`, and drives one node and the
//! far ends there: no administrator is asked, and nothing outside the
//! namespace sees an interface. Linux's alone. Where the machine grants no
//! such namespace, or makes no virtual CAN interface or veth pair in one,
//! the test says so and runs nothing; where it does, every far end stands,
//! and one that does not fails the test.

use std::process::Command;

use super::far_ends;
use super::linked::carried;

/// Set on the test where it runs inside its namespace.
const INSIDE: &str = "XMIP_TEST_NAMESPACED";

/// The test's own path, as libtest filters for it, run again inside.
const TEST: &str = "namespaced::a_file_dropped_in_is_sent_over_every_kernel_link_to_its_far_end";

/// What `unshare` is asked for: a user namespace whose root is the account,
/// and a network namespace it owns.
const NAMESPACES: [&str; 3] = ["--user", "--map-root-user", "--net"];

/// What the machine is asked to make, in a namespace of its own, before
/// the test runs: an interface of each kind the far ends stand on.
const PROBE: &str = "ip link add xmip-probe type vcan && \
                     ip link add xmip-probe-a type veth peer name xmip-probe-b";

#[test]
fn a_file_dropped_in_is_sent_over_every_kernel_link_to_its_far_end() {
    if std::env::var_os(INSIDE).is_none() {
        entered();
        return;
    }
    made();
    carried("service-kernel", |_| far_ends::kernel::kernel());
}

/// This test run again inside its namespace, its outcome this one's; where
/// this machine grants no namespace, or makes no interface of a kind in
/// one, said, and nothing run.
fn entered() {
    let probe = Command::new("unshare")
        .args(NAMESPACES)
        .args(["sh", "-c", PROBE])
        .output();
    match probe {
        Ok(probe) if probe.status.success() => {}
        Ok(probe) => {
            let said = String::from_utf8_lossy(&probe.stderr);
            println!("kernel links: not on this machine: {}", said.trim());
            return;
        }
        Err(why) => {
            println!("kernel links: not on this machine: unshare: {why}");
            return;
        }
    }
    let test = std::env::current_exe().expect("this test's program");
    let status = Command::new("unshare")
        .args(NAMESPACES)
        .arg("--")
        .arg(test)
        .args([TEST, "--exact", "--nocapture"])
        .env(INSIDE, "1")
        .status()
        .expect("unshare runs");
    assert!(status.success(), "inside its namespace: {status}");
}

/// The loopback interface up, IPv6 off so no interface speaks on its own,
/// and every interface the far ends stand on made and up: a virtual CAN
/// interface each, a veth pair each.
fn made() {
    ip(&["link", "set", "lo", "up"]);
    for sysctl in ["all", "default"] {
        let path = format!("/proc/sys/net/ipv6/conf/{sysctl}/disable_ipv6");
        std::fs::write(&path, "1").unwrap_or_else(|why| panic!("{path}: {why}"));
    }
    for interface in far_ends::kernel::CAN {
        ip(&["link", "add", "dev", interface, "type", "vcan"]);
        ip(&["link", "set", interface, "up"]);
    }
    for (near, far) in far_ends::kernel::ETHERNET {
        ip(&["link", "add", near, "type", "veth", "peer", "name", far]);
        ip(&["link", "set", near, "up"]);
        ip(&["link", "set", far, "up"]);
    }
}

/// `ip` with `arguments`, done, or the test failed with what it said.
fn ip(arguments: &[&str]) {
    let output = Command::new("ip")
        .args(arguments)
        .output()
        .unwrap_or_else(|why| panic!("ip: {why}"));
    assert!(
        output.status.success(),
        "ip {}: {}",
        arguments.join(" "),
        String::from_utf8_lossy(&output.stderr).trim()
    );
}
