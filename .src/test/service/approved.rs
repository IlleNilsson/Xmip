//! A node runs the System Tests' Work Process *Order approval* end to end
//! (open problem 87). Its unit — the System Tests' example `order_approval`,
//! generated from `order-approval.bpmn`, which this crate builds too as
//! `order_approval_unit` — is opened from beside the node's configuration
//! through the C ABI as `xmip-service` starts (ADR-0066 clause 4). A sales
//! order dropped in is handed to it by the Subscription *Sales orders*,
//! marked `Approval = 'approved'` and published again as a new generation,
//! and *Approved sales orders* takes it to the ERP's folder, whole: nothing
//! reaches the ERP but through the Work Process. The module, the Work
//! Process entry and both Subscriptions are read from the Reference
//! Environment, so this node runs what the System Tests' nodes run.

use std::path::Path;
use std::time::{Duration, Instant};

use super::folder::{dropped, named, quoted};
use super::routed::{ORDERS, sent};
use super::{Ending, exited, heard, lines, spawned, stop, test_cluster, told, watched};

/// The Reference Environment, beside the System Tests' design.
const CLUSTER: &str = "test/core/system-test/configuration/cluster.xmip";

/// Their Application, its Work Process and the Subscriptions into and out
/// of it.
const APPLICATION: &str = "Order to cash";
const PROCESS: &str = "Order approval";
const INTO: &str = "Sales orders";
const OUT: &str = "Approved sales orders";

/// The library this crate builds the unit into.
const BUILT: &str = "order_approval_unit";

/// What bounds the order's way from its drop to the ERP: a bound on the
/// test, never on Xmip.
const CARRY: Duration = Duration::from_secs(20);

/// The one entry named `name` of the array `key` in `table`.
fn entry<'a>(table: &'a toml::Table, key: &str, name: &str) -> &'a toml::Table {
    table[key]
        .as_array()
        .and_then(|all| {
            all.iter().filter_map(toml::Value::as_table).find(|one| {
                let named = one.get("name").or_else(|| one.get("id"));
                named.and_then(toml::Value::as_str) == Some(name)
            })
        })
        .unwrap_or_else(|| panic!("the System Tests declare {key} '{name}'"))
}

/// The node, its own Storage node, receiving from `inbox` and sending to
/// `erp` the System Tests' way, through their Work Process; and the
/// library the module names, as this system names it.
fn configuration(directory: &Path, inbox: &Path, erp: &Path) -> (String, String) {
    let text = std::fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join(CLUSTER))
        .expect("the Reference Environment");
    let cluster: toml::Table = text.parse().expect("TOML");
    let application = entry(&cluster, "xmip_applications", APPLICATION);
    let process = entry(application, "work_processes", PROCESS);
    let module = process["module"].as_str().expect("its module");
    let unit = process["unit"].as_str().expect("its unit");
    let modules = toml::Table::from_iter([(
        "modules".to_string(),
        toml::Value::Array(vec![toml::Value::Table(
            entry(&cluster, "modules", module).clone(),
        )]),
    )]);
    let filter = |id: &str| entry(application, "subscriptions", id)["filter"].to_string();
    let port = entry(application, "subscriptions", OUT)["destination"]["send-port"]
        .as_str()
        .expect("the ERP's Send Port")
        .to_string();
    let (cluster_name, node) = (&test_cluster().name, &test_cluster().node(0).name);
    let text = format!(
        "roles = \"executing, storage\"\n\n[service]\nname = \"xmip-{node}\"\n\
         cluster_name = \"{cluster_name}\"\nnode_name = \"{node}\"\n\n\
         [tuning]\nsend_scan = \"50ms\"\nreceive_backoff = \"50ms\"\n\n\
         [[applications]]\nname = {application_name}\n\n\
         [[applications.receive_locations]]\nname = \"In\"\nnode = {node_name}\naddress = {}\n\
         [applications.receive_locations.accept]\nmechanism = [\"circumstance\"]\n\
         transport = \"claimed\"\n\n\
         [[applications.send_ports]]\nname = {port_name}\nnode = {node_name}\naddress = {}\n\n\
         [[applications.work_processes]]\nname = {process_name}\nnode = {node_name}\n\n\
         [[xmip_applications]]\nname = {application_name}\n\n\
         [[xmip_applications.receive_ports]]\nname = \"In\"\n\n\
         [[xmip_applications.receive_locations]]\nname = \"In\"\nreceive_port = \"In\"\n\
         depth = \"light\"\n\n[[xmip_applications.send_ports]]\nname = {port_name}\n\n\
         [[xmip_applications.work_processes]]\nname = {process_name}\nmodule = {}\nunit = {}\n\n\
         [[xmip_applications.subscriptions]]\nid = {}\n\
         destination = {{ work-process = {process_name} }}\nfilter = {}\n\n\
         [[xmip_applications.subscriptions]]\nid = {}\n\
         destination = {{ send-port = {port_name} }}\nfilter = {}\n\n\
         [operate]\nlocal = {}\n\n{modules}",
        quoted(&named(inbox)),
        quoted(&named(erp)),
        quoted(module),
        quoted(unit),
        quoted(INTO),
        filter(INTO),
        quoted(OUT),
        filter(OUT),
        quoted(&super::endpoint(directory)),
        application_name = quoted(APPLICATION),
        node_name = quoted(node),
        port_name = quoted(&port),
        process_name = quoted(PROCESS),
    );
    (text, xmip_process::generate::library_file(module))
}

#[test]
fn a_sales_order_passes_the_system_tests_order_approval_on_its_way_to_the_erp() {
    let directory = xmip_file::temporary::Folder::new("service-approved");
    let (inbox, erp) = (directory.join("in"), directory.join("erp"));
    for folder in [&inbox, &erp] {
        std::fs::create_dir_all(folder).expect("a folder");
    }
    let (text, library) = configuration(&directory, &inbox, &erp);
    let folder = xmip_runtime::fixture::configuration_folder(&directory);
    std::fs::create_dir_all(&folder).expect("the configuration's folder");
    let built = Path::new("examples").join(xmip_abi::boundaries::library_file_name(BUILT));
    let built = xmip_file::built::found(&built).unwrap_or_else(|| {
        panic!(
            "no {} above this test: cargo test builds it",
            built.display()
        )
    });
    std::fs::copy(&built, folder.join(&library)).expect("the unit beside the configuration");
    let path = folder.join("node.xmip");
    xmip_runtime::fixture::write_signed(&path, &text);
    let mut child = spawned(&path, &directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        &format!("{} accepts work", test_cluster().node_scope(0)),
        Duration::from_secs(20),
    );
    let (to_erp, _watch) = watched(&erp);

    dropped(&directory, &inbox, "order.edi", ORDERS);
    told(&to_erp, Instant::now() + CARRY, || !sent(&erp).is_empty());

    assert_eq!(
        sent(&erp),
        ["order.edi"],
        "the order, through Order approval"
    );
    assert_eq!(
        std::fs::read_to_string(erp.join("order.edi")).expect("sent"),
        ORDERS,
        "whole"
    );
    stop(&child);
    heard(&said, "stopped by the console", Duration::from_secs(10));
    assert!(exited(child, Duration::from_secs(10)).success());
    ending.0 = None;
}
