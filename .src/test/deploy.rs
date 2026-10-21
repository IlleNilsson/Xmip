//! Every node configuration `deploy/` writes, read the way `xmip-service`
//! reads its own: the Playground's cluster `xmip.toml` — the one file a
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
//! inventory maps only nodes the file declares. The Microsoft DSC v3
//! documents are held by `test/MsdscEnvironment.Test.ps1`.

use std::path::{Path, PathBuf};

use xmip_configure::XmipConfigurationDocument;
use xmip_runtime::catalogue;
use xmip_runtime::execution_tree::build_execution_tree;

const PLAYGROUND: &str = "test/core/playground/configuration/xmip.toml";
const TASKS_WINDOWS: &str = "deploy/dsc/ansible/roles/xmip_node/tasks/windows.yml";
const TASKS_LINUX: &str = "deploy/dsc/ansible/roles/xmip_node/tasks/linux.yml";
const INVENTORY: &str = "deploy/dsc/ansible/inventory.example.yml";

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
    let config = directory.join(name).join("config");
    std::fs::create_dir_all(&config).expect("creates the layout");
    let path: PathBuf = config.join("xmip-node.toml");
    std::fs::write(&path, text).expect("writes the configuration");

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
fn every_node_configuration_deploy_writes_is_the_one_the_runtime_reads() {
    let directory = std::env::temp_dir().join(format!("xmip-deploy-{}", std::process::id()));

    for tasks in [TASKS_WINDOWS, TASKS_LINUX] {
        let text = source(tasks);
        for asked in ["xmip-service", "--slice", "--cluster", "--listening"] {
            assert!(
                text.contains(asked),
                "{tasks} asks xmip-service for the slice, its cluster and its ports: {asked}"
            );
        }
    }
    assert!(
        !Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("deploy/dsc/ansible/roles/xmip_node/templates")
            .exists(),
        "the role writes no starter of its own: the package's xmip-service --install does"
    );

    // The Playground's file is the one a test runs whether its nodes are
    // simulated or on machines of their own (ADR-0028, amendment
    // 2026-10-21): every node it declares slices as the environment names
    // the cluster and reads as xmip-service reads it.
    let cluster = source(PLAYGROUND);
    assert_eq!(
        xmip_configure::cluster::cluster_name(&cluster).expect("reads"),
        None,
        "{PLAYGROUND} names no cluster: where it runs is the environment's"
    );
    let environment = xmip_configure::fixture::test_cluster().name;
    let nodes = xmip_configure::cluster::nodes(&cluster).expect("declares its nodes");
    assert!(!nodes.is_empty(), "{PLAYGROUND} declares its nodes");
    for node in &nodes {
        let text = xmip_configure::slice_named(&cluster, node, &environment)
            .unwrap_or_else(|problem| panic!("{node} does not slice: {problem}"));
        let document = read(&directory, &format!("playground-{node}"), &text);
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

    // The example environment puts only nodes the file declares on machines.
    let inventory = source(INVENTORY);
    for line in inventory
        .lines()
        .filter(|line| line.contains("xmip_node_name:"))
    {
        let named = line.split(':').nth(1).unwrap_or_default().trim();
        assert!(
            nodes.iter().any(|node| node == named),
            "{INVENTORY} maps {named}, which {PLAYGROUND} does not declare"
        );
    }

    std::fs::remove_dir_all(&directory).expect("removes what it wrote");
}
