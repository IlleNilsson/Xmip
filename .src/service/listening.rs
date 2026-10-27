//! `--listening`: each port the node's configuration listens on, one line
//! each, `<port>/<protocol> <listener>` — what an environment opens its
//! firewall for, and nothing else (ADR-0015, amendment 2026-10-21). The
//! environment templates ask this and never read the configuration
//! themselves.
//!
//! What listens is what the configuration says: the operate listener at
//! `[operate] listen`, the Storage listener at `[storage] listen` where the
//! node declares the Storage role, and each started Receive Location, its own and its
//! bindings', whose address names a port and whose technology waits for
//! what is sent to it — never one that goes to look, as an SFTP Location
//! fetching from a far end does (`LinkedTransport::waits`) — over TCP. The
//! cluster's authority, where `[provision.node]` serves it, listens at its
//! `serve` and `publish` addresses (ADR-0034, amendment 2026-10-22). A
//! Receive Location whose
//! transport listens on UDP is said over TCP too until a transport declares
//! the protocol it listens on, which none does yet.

use std::process::ExitCode;

use xmip_audit::program_audit::ProgramAudit;
use xmip_configure::XmipConfigurationDocument;
use xmip_runtime::registration::REFUSED;

use crate::arguments::Arguments;
use crate::run;

/// Print the ports, or refuse in words.
pub fn print(audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    match xmip_runtime::start::read(&arguments.configuration) {
        Ok((document, _, _)) => {
            for line in listening(&document) {
                println!("{line}");
            }
            ExitCode::SUCCESS
        }
        Err(unread) => {
            run::fail(
                audit,
                "listening",
                &format!("xmip-service: {}", unread.reason),
            );
            ExitCode::from(REFUSED)
        }
    }
}

/// The node's listeners, `<port>/tcp <listener>`, in the order the
/// configuration says them, each port once.
fn listening(document: &XmipConfigurationDocument) -> Vec<String> {
    let node = &document.service.node_name;
    let mut said: Vec<(u16, String)> = Vec::new();
    let operate = document
        .operate
        .as_ref()
        .and_then(|operate| operate.listen.as_deref());
    if let Some(port) = operate.and_then(port_of) {
        said.push((port, "operate".to_string()));
    }
    // Only a node declaring the Storage role serves Xmip Storage.
    let roles = xmip_node::NodeRole::declared(document.roles.as_deref().unwrap_or(""));
    let stores = roles.is_ok_and(|roles| roles.contains(&xmip_node::NodeRole::Storage));
    let storage = document.storage.listen.as_deref().filter(|_| stores);
    if let Some(port) = storage.and_then(port_of) {
        said.push((port, "storage".to_string()));
    }
    for (address, what) in crate::authority::listens(document) {
        if let Some(port) = port_of(&address) {
            said.push((port, what.to_string()));
        }
    }
    let own = document.receive_locations.iter();
    let bound = document
        .applications
        .iter()
        .flat_map(|application| &application.receive_locations)
        .filter(|bound| bound.node == *node)
        .map(|bound| &bound.location);
    let linked = crate::built::transports();
    // A Location whose technology goes to look — a folder, an SFTP server
    // it fetches from — listens on nothing, whatever port its address names.
    let waits = |location: &&xmip_configure::ConfiguredLocation| {
        linked
            .iter()
            .find(|one| one.technology() == location.transport)
            .is_none_or(|one| one.waits(location))
    };
    for location in own
        .chain(bound)
        .filter(|location| location.start)
        .filter(waits)
    {
        if let Some(port) = port_of(&location.address) {
            said.push((port, format!("receive location {}", location.name)));
        }
    }
    let mut seen = Vec::new();
    said.into_iter()
        .filter(|(port, _)| {
            let first = !seen.contains(port);
            seen.push(*port);
            first
        })
        .map(|(port, listener)| format!("{port}/tcp {listener}"))
        .collect()
}

/// The port an address names: `host:port`, `[v6]:port`, or the authority of
/// `scheme://host:port/path`. None for a path or an address with no port.
fn port_of(address: &str) -> Option<u16> {
    let authority = address
        .split_once("://")
        .map_or(address, |(_, rest)| rest)
        .split(['/', '?'])
        .next()?;
    let (_, port) = authority.rsplit_once(':')?;
    port.parse().ok().filter(|port| *port > 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_port_is_read_from_every_address_that_names_one() {
        assert_eq!(port_of("0.0.0.0:7401"), Some(7401));
        assert_eq!(port_of("[::]:7401"), Some(7401));
        assert_eq!(port_of("http://0.0.0.0:8080/orders"), Some(8080));
        assert_eq!(port_of("/var/xmip/in"), None);
        assert_eq!(port_of("D:/Xmip/in"), None);
        assert_eq!(port_of("host:0"), None);
    }

    #[cfg(feature = "transport-sftp")]
    #[test]
    fn a_location_fetching_from_the_parties_far_end_listens_on_nothing() {
        let cluster = xmip_configure::fixture::test_cluster();
        let node = cluster.with_role("receiving").name.clone();
        let file = format!(
            "[nodes.{node}]\nroles = \"receiving\"\n\
             [[xmip_applications]]\nname = \"Orders\"\n\
             [[xmip_applications.receive_ports]]\nname = \"In\"\n\
             [[xmip_applications.receive_locations]]\nname = \"From A\"\nreceive_port = \"In\"\n\
             interaction = \"data-transfer\"\ndepth = \"light\"\n"
        );
        let placed =
            xmip_configure::placed::at_far_end(&file, std::slice::from_ref(&node), "10.77.0.1")
                .expect("placed");
        let text = xmip_configure::slice_named(&placed, &node, "listening").expect("slices");
        let document = xmip_configure::parse_toml(&text).expect("reads");
        assert!(
            listening(&document).is_empty(),
            "{:?}",
            listening(&document)
        );
    }

    #[test]
    fn the_operate_listener_and_each_started_receive_location_with_a_port_listen() {
        let cluster = xmip_configure::fixture::test_cluster();
        let node = cluster.node(0).name.clone();
        let other = cluster.with_role("receiving").name.clone();
        let file = format!(
            "[operate]\nlisten = \"0.0.0.0:7401\"\ncertificate = \"node.pem\"\n\
             key = \"node.key\"\nanchors = \"anchors.pem\"\n\
             [[receive_locations]]\nname = \"orders\"\nstart = true\n\
             transport = \"xmip-core-transport-tcp\"\naddress = \"0.0.0.0:9100\"\n\
             [[receive_locations]]\nname = \"stopped\"\nstart = false\n\
             transport = \"xmip-core-transport-tcp\"\naddress = \"0.0.0.0:9101\"\n\
             [[receive_locations]]\nname = \"drop\"\nstart = true\n\
             transport = \"xmip-core-transport-file\"\naddress = \"/var/xmip/in\"\n\
             [storage]\nlisten = \"0.0.0.0:7443\"\n\
             [nodes.{node}]\nroles = \"storage\"\n[nodes.{other}]\nroles = \"receiving\"\n"
        );
        let text = xmip_configure::slice_named(&file, &node, "listening").expect("slices");
        let document = xmip_configure::parse_toml(&text).expect("reads");
        assert_eq!(
            listening(&document),
            [
                "7401/tcp operate",
                "7443/tcp storage",
                "9100/tcp receive location orders"
            ]
        );
        let text = xmip_configure::slice_named(&file, &other, "listening").expect("slices");
        let document = xmip_configure::parse_toml(&text).expect("reads");
        assert!(
            !listening(&document).contains(&"7443/tcp storage".to_string()),
            "only a node declaring the Storage role serves it"
        );
    }
}
