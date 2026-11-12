//! A node routes by what the document says (the owner, 2026-11-10: *the
//! Essentials test, promotion thing*; ADR-0046, amendment 2026-11-11): its
//! Subscriptions read the message type and the recipient an EDIFACT
//! interchange carries, `content:edi:UNH/2/1` and `content:edi:UNB/3/1`,
//! through the `content` route technology and the `edi` path language this
//! build links. An order dropped into its file Receive Location goes to the
//! Send Port the orders Subscription names, an invoice to the invoices one,
//! each whole; a status message no Subscription takes goes to neither.
//! Until 2026-11-11 the service linked no route technology, and a node
//! whose filter named one refused to start.

use std::path::Path;
use std::time::{Duration, Instant};

use super::{Ending, exited, heard, lines, spawned, stop, test_cluster, told, watched};

/// An order, as a trading Party sends one.
const ORDERS: &str = "UNB+UNOC:3+PARTY-A:ZZZ+ESSENTIALS:ZZZ+261111:0905+A0001'\n\
UNH+1+ORDERS:D:24A:UN'\nBGM+220+PO-A-4711+9'\nDTM+137:20261111:102'\n\
NAD+BY+PARTY-A::ZZZ'\nLIN+1++4006381333931:SRS'\nQTY+21:120:PCE'\nUNS+S'\n\
UNT+8+1'\nUNZ+1+A0001'\n";

/// An invoice to that Party.
const INVOIC: &str = "UNB+UNOC:3+ESSENTIALS:ZZZ+PARTY-A:ZZZ+261111:1600+S0003'\n\
UNH+1+INVOIC:D:24A:UN'\nBGM+380+INV-1001+9'\nDTM+137:20261111:102'\n\
MOA+86:1086.00'\nUNT+5+1'\nUNZ+1+S0003'\n";

/// A status message, which no Subscription takes.
const IFTSTA: &str = "UNB+UNOC:3+PARTY-A:ZZZ+ESSENTIALS:ZZZ+261111:1205+A9001'\n\
UNH+1+IFTSTA:D:24A:UN'\nBGM+77+ST-9001+9'\nUNT+3+1'\nUNZ+1+A9001'\n";

/// What bounds a file's way from its drop to its Send Port's folder: a
/// bound on the test, never on Xmip.
const CARRY: Duration = Duration::from_secs(20);

/// A path as a configuration names it.
fn named(path: &Path) -> String {
    path.display().to_string().replace('\\', "/")
}

/// The node, its own Storage node, routing what `drop` takes to `orders`
/// or `invoices` by the document's own words.
fn configuration(drop: &Path, orders: &Path, invoices: &Path) -> String {
    let (cluster, node) = (&test_cluster().name, &test_cluster().node(0).name);
    let local = format!("xmip-routed-{}", std::process::id());
    let (drop, orders, invoices) = (named(drop), named(orders), named(invoices));
    format!(
        r#"roles = "executing, storage"

[service]
name = "xmip-{node}"
cluster_name = "{cluster}"
node_name = "{node}"

[tuning]
send_scan = "50ms"
receive_backoff = "50ms"

[[applications]]
name = "Routed"

[[applications.receive_locations]]
name = "In"
node = "{node}"
address = "{drop}"
[applications.receive_locations.accept]
mechanism = ["circumstance"]
transport = "claimed"

[[applications.send_ports]]
name = "Orders"
node = "{node}"
address = "{orders}"

[[applications.send_ports]]
name = "Invoices"
node = "{node}"
address = "{invoices}"

[[xmip_applications]]
name = "Routed"

[[xmip_applications.receive_ports]]
name = "Routed"

[[xmip_applications.receive_locations]]
name = "In"
receive_port = "Routed"
depth = "light"

[[xmip_applications.send_ports]]
name = "Orders"

[[xmip_applications.send_ports]]
name = "Invoices"

[[xmip_applications.subscriptions]]
id = "Sales orders"
destination = {{ send-port = "Orders" }}
filter = "\"content:edi:UNH/2/1\" = 'ORDERS' and \"content:edi:UNB/3/1\" = 'ESSENTIALS'"

[[xmip_applications.subscriptions]]
id = "Invoices"
destination = {{ send-port = "Invoices" }}
filter = "\"content:edi:UNH/2/1\" = 'INVOIC' and \"content:edi:UNB/3/1\" = 'PARTY-A'"

[operate]
local = "{local}"
"#
    )
}

/// The files whole in `folder`, by name: none a send is still writing.
fn sent(folder: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(folder)
        .map(|entries| {
            entries
                .filter_map(Result::ok)
                .map(|entry| entry.file_name().to_string_lossy().into_owned())
                .filter(|name| !name.contains(".xmip-"))
                .collect()
        })
        .unwrap_or_default();
    names.sort();
    names
}

/// `text` dropped into `drop` as `name`, written beside and renamed in.
fn dropped(directory: &Path, drop: &Path, name: &str, text: &str) {
    let beside = directory.join(format!("{name}.part"));
    std::fs::write(&beside, text).expect("written");
    std::fs::rename(&beside, drop.join(name)).expect("dropped");
}

#[test]
fn an_edifact_document_goes_to_the_send_port_its_message_type_and_recipient_name() {
    let directory =
        std::env::temp_dir().join(format!("xmip-service-routed-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let (drop, orders, invoices) = (
        directory.join("in"),
        directory.join("orders"),
        directory.join("invoices"),
    );
    for folder in [&drop, &orders, &invoices] {
        std::fs::create_dir_all(folder).expect("a folder");
    }
    let path = xmip_runtime::fixture::configuration_folder(&directory).join("node.xmip");
    xmip_runtime::fixture::write_signed(&path, &configuration(&drop, &orders, &invoices));
    let mut child = spawned(&path, &directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        &format!("{} accepts work", test_cluster().node_scope(0)),
        Duration::from_secs(20),
    );
    let (to_orders, _orders_watch) = watched(&orders);
    let (to_invoices, _invoices_watch) = watched(&invoices);

    dropped(&directory, &drop, "status.edi", IFTSTA);
    dropped(&directory, &drop, "order.edi", ORDERS);
    dropped(&directory, &drop, "invoice.edi", INVOIC);
    let deadline = Instant::now() + CARRY;
    told(&to_orders, deadline, || !sent(&orders).is_empty());
    told(&to_invoices, deadline, || !sent(&invoices).is_empty());

    assert_eq!(sent(&orders), ["order.edi"], "the order, and only it");
    assert_eq!(sent(&invoices), ["invoice.edi"], "the invoice, and only it");
    assert_eq!(
        std::fs::read_to_string(orders.join("order.edi")).expect("sent"),
        ORDERS,
        "whole"
    );
    assert_eq!(
        std::fs::read_to_string(invoices.join("invoice.edi")).expect("sent"),
        INVOIC,
        "whole"
    );
    stop(&child);
    heard(&said, "stopped by the console", Duration::from_secs(10));
    assert!(exited(child, Duration::from_secs(10)).success());
    ending.0 = None;
    let _ = std::fs::remove_dir_all(&directory);
}
