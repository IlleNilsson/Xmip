//! Every node configuration `deploy/` writes, read the way `xmip-service`
//! reads its own: the Essentials' cluster `cluster.xmip` — the one file a
//! test runs whether its nodes are simulated or on machines of their own
//! (ADR-0028, amendment 2026-10-21), which the environment templates under
//! `deploy/dsc` put on each node machine — sliced to every node it declares
//! by `xmip_configure::slice_named`, as `xmip-service --slice --cluster`
//! prints it, then `xmip_runtime::start::read` and the execution tree
//! against the technologies the runtime carries. The reader keeps no key it
//! does not know, so each key the slice writes must also come back when the
//! document the reader made of it is written out: a file naming a key the
//! reader drops fails here, not on an installed node.
//!
//! The Ansible role asks `xmip-service` for the slice, its cluster and the
//! ports the firewall opens, and keeps no starter of its own; the example
//! environment files, from which both technologies' parameters are written
//! (`deploy/dsc/README.md`), map only nodes the file declares, and every
//! Location the file designs is placed on one of the Hyper-V example's, bound
//! on the Parties' far end, in a slice the runtime reads. The Microsoft DSC
//! v3 documents are held by `test/MsdscEnvironment.Test.ps1`.

use std::path::{Path, PathBuf};

use xmip_configure::XmipConfigurationDocument;
use xmip_runtime::catalogue;
use xmip_runtime::execution_tree::build_execution_tree;

const ESSENTIALS: &str = "test/core/essentials/configuration/cluster.xmip";
const TASKS_WINDOWS: &str = "deploy/dsc/ansible/roles/xmip_node/tasks/windows.yml";
const TASKS_LINUX: &str = "deploy/dsc/ansible/roles/xmip_node/tasks/linux.yml";
const TASKS_SLICE: &str = "deploy/dsc/ansible/roles/xmip_node/tasks/slice.yml";
/// The example environment files: the one place each says which node runs
/// on which machine, `[[machines]]`' `nodes`.
const ENVIRONMENTS: [&str; 2] = [
    "deploy/dsc/hyperv.example.toml",
    "deploy/dsc/libvirt.example.toml",
];
const DEFAULTS: &str = "deploy/dsc/ansible/roles/xmip_node/defaults/main.yml";

fn source(relative: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(relative);
    std::fs::read_to_string(&path).unwrap_or_else(|error| panic!("{relative}: {error}"))
}
/// Every key path in `table`, tables descended into.
fn keys(table: &toml::Table, prefix: &str) -> Vec<String> {
    let mut paths = Vec::new();
    for (key, value) in table {
        let path = if prefix.is_empty() {
            key.clone()
        } else {
            format!("{prefix}.{key}")
        };
        if let toml::Value::Table(inner) = value {
            paths.extend(keys(inner, &path));
        }
        paths.push(path);
    }
    paths
}

/// The nodes an environment file maps onto its machines, in its order.
fn mapped_by(relative: &str) -> Vec<String> {
    let environment: toml::Table = source(relative)
        .parse()
        .unwrap_or_else(|error| panic!("{relative} is TOML: {error}"));
    environment
        .get("machines")
        .and_then(toml::Value::as_array)
        .unwrap_or_else(|| panic!("{relative} lists its [[machines]]"))
        .iter()
        .filter_map(|machine| machine.get("nodes").and_then(toml::Value::as_array))
        .flatten()
        .filter_map(toml::Value::as_str)
        .map(str::to_string)
        .collect()
}

fn holds(table: &toml::Table, path: &str) -> bool {
    let mut at = table;
    let mut parts = path.split('.').peekable();
    while let Some(part) = parts.next() {
        match (at.get(part), parts.peek()) {
            (Some(_), None) => return true,
            (Some(toml::Value::Table(inner)), Some(_)) => at = inner,
            _ => return false,
        }
    }
    false
}

/// Write `text` where an installed node keeps it, read it as `xmip-service`
/// does, and hold every key it writes to what the reader kept.
fn read(directory: &Path, name: &str, text: &str) -> XmipConfigurationDocument {
    let config = xmip_runtime::fixture::configuration_folder(&directory.join(name));
    let path: PathBuf = config.join("node.xmip");
    xmip_runtime::fixture::write_signed(&path, text);

    let (document, applications, _) = xmip_runtime::start::read(&path.to_string_lossy())
        .unwrap_or_else(|unread| panic!("{name} is refused: {}\n{text}", unread.reason));
    if let Err(report) =
        build_execution_tree(document.clone(), &applications, &catalogue::declarations())
    {
        panic!(
            "{name} does not start: {}\n{text}",
            report.errors.join("; ")
        );
    }

    let written: toml::Table = text.parse().expect("the rendered text is TOML");
    let kept: toml::Table = toml::to_string(&document)
        .expect("the reader's document writes")
        .parse()
        .expect("and reads back");
    for path in keys(&written, "") {
        assert!(
            holds(&kept, &path),
            "{name} writes {path}, which the node configuration reader does not keep\n{text}"
        );
    }
    document
}

#[test]
fn the_controller_slices_and_signs_and_a_node_never_slices() {
    // The controller slices and signs each node's configuration with the
    // environment's authority; a node is given the slice and the authority's
    // certificate, never slices and never holds the key (ADR-0031,
    // amendment 2026-11-06).
    let slicing = source(TASKS_SLICE);
    for asked in [
        "--slice",
        "--cluster",
        "--authority",
        "xmip_bound",
        "delegate_to: localhost",
    ] {
        assert!(
            slicing.contains(asked),
            "{TASKS_SLICE} slices and signs on the controller: {asked}"
        );
    }
    for tasks in [TASKS_WINDOWS, TASKS_LINUX] {
        let text = source(tasks);
        for asked in [
            "xmip_slice.stdout",
            "authority.pem",
            "[signature]",
            "--listening",
        ] {
            assert!(
                text.contains(asked),
                "{tasks} places the signed slice and its authority's certificate: {asked}"
            );
        }
        assert!(
            !text.contains("--slice") && !text.contains("cluster.xmip'"),
            "{tasks} never slices on the node"
        );
    }
    assert!(
        !Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("deploy/dsc/ansible/roles/xmip_node/templates")
            .exists(),
        "the role writes no starter of its own: the package's xmip-service --install does"
    );
}

#[test]
fn every_node_configuration_deploy_writes_is_the_one_the_runtime_reads() {
    let directory = std::env::temp_dir().join(format!("xmip-deploy-{}", std::process::id()));

    // The Essentials' file is the one a test runs whether its nodes are
    // simulated or on machines of their own (ADR-0028, amendment
    // 2026-10-21): every node it declares slices as the environment names
    // the cluster and reads as xmip-service reads it.
    let cluster = source(ESSENTIALS);
    assert_eq!(
        xmip_configure::cluster::cluster_name(&cluster).expect("reads"),
        None,
        "{ESSENTIALS} names no cluster: where it runs is the environment's"
    );
    let environment = xmip_configure::fixture::test_cluster().name;
    let nodes = xmip_configure::cluster::nodes(&cluster).expect("declares its nodes");
    assert!(!nodes.is_empty(), "{ESSENTIALS} declares its nodes");
    for node in &nodes {
        let text = xmip_configure::slice_named(&cluster, node, &environment)
            .unwrap_or_else(|problem| panic!("{node} does not slice: {problem}"));
        let document = read(&directory, &format!("essentials-{node}"), &text);
        assert_eq!(document.service.cluster_name, environment);
        assert_eq!(document.service.node_name, *node);
        let operate = document
            .operate
            .expect("each node is operated from another machine");
        assert!(
            operate
                .listen
                .is_some_and(|listen| listen.starts_with("0.0.0.0:")),
            "{node} listens at whatever address its machine has"
        );
    }

    // Each example environment puts only nodes the file declares on machines.
    for environment in ENVIRONMENTS {
        let named = mapped_by(environment);
        assert!(!named.is_empty(), "{environment} maps nodes onto machines");
        for one in &named {
            assert!(
                nodes.iter().any(|node| node == one),
                "{environment} maps {one}, which {ESSENTIALS} does not declare"
            );
        }
    }
    // The Hyper-V example's nodes are the ones every Location is placed over.
    let mapped = mapped_by(ENVIRONMENTS[0]);

    // Every node it maps, its Locations placed over the mapped nodes on the
    // Parties' far end as `xmip-service --slice --bind --nodes` places them
    // (ADR-0028, amendment 2026-10-22), reads as xmip-service reads it, and
    // every Location the file designs is placed on one of them.

    assert!(source(DEFAULTS).contains("'--bind', xmip_far_end, '--nodes'"));
    let bound = xmip_configure::placed::at_far_end(&cluster, &mapped, "10.77.0.1")
        .expect("places over the mapped nodes");
    let mut placed = 0;
    for node in &mapped {
        let text = xmip_configure::slice_named(&bound, node, &environment)
            .unwrap_or_else(|problem| panic!("{node} does not slice bound: {problem}"));
        let document = read(&directory, &format!("bound-{node}"), &text);
        placed += document
            .applications
            .iter()
            .flat_map(|one| one.receive_locations.iter().chain(&one.send_ports))
            .filter(|bound| bound.node == *node)
            .count();
    }
    let designed: usize = xmip_configure::applications(&cluster)
        .expect("designs")
        .iter()
        .map(|one| one.receive_locations.len() + one.send_ports.len())
        .sum();
    assert_eq!(
        placed, designed,
        "every Location is placed on a mapped node"
    );

    std::fs::remove_dir_all(&directory).expect("removes what it wrote");
}
