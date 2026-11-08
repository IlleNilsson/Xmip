//! The starter `cluster.xmip` `--install` writes where a machine has none
//! of its own (ADR-0015, amendment 2026-10-13): one node, offline
//! (ADR-0045), keeping Xmip Storage itself (ADR-0056, amendment
//! 2026-10-20), operated on its local endpoint, which always starts named
//! `xmip-<node>` as its service is (ADR-0014, amendments 2026-10-13), by the
//! account that installed it, its one operator (ADR-0009, amendment
//! 2026-11-07).

use xmip_runtime::registration::node_service_name;

use crate::install::NODE_FILE;

/// The starter `cluster.xmip` of a one-node cluster: what a package writes
/// where the machine has none of its own, `operator`, the account that
/// installs, its one operator.
pub fn starter(cluster: &str, node: &str, operator: &str) -> String {
    let service = node_service_name(node);
    format!(
        "# The cluster's configuration, cluster.xmip, as an Xmip package starts it:\n\
         # one node, offline, operated from this machine on its local endpoint,\n\
         # {service}, which always starts (ADR-0015, amendment 2026-10-13;\n\
         # ADR-0014, amendments 2026-10-13). The node's configuration,\n\
         # {NODE_FILE}, is sliced from this file; change this one, slice again\n\
         # (xmip-service --slice) and restart the service.\n\
         [service]\n\
         name = {service}\n\
         cluster_name = {cluster}\n\
         \n\
         # One node, so it keeps Xmip Storage itself: only a node with the\n\
         # storage role stores (ADR-0056, amendment 2026-10-20).\n\
         [nodes.{node_key}]\n\
         roles = \"storage\"\n\
         \n\
         [nodes.{node_key}.service]\n\
         online = false\n\
         \n\
         # Who operates it: the account that installed it. A caller no list\n\
         # names holds no role (ADR-0009, amendment 2026-11-07); add others\n\
         # to observers, operators or developers.\n\
         [nodes.{node_key}.operate]\n\
         operators = [{operator}]\n",
        service = quoted(&service),
        cluster = quoted(cluster),
        node_key = quoted(node),
        operator = quoted(operator),
    )
}

/// `text` as a TOML basic string.
fn quoted(text: &str) -> String {
    format!("\"{}\"", text.replace('\\', "\\\\").replace('"', "\\\""))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::definition::text;

    /// The starter slices for its node and reads as `xmip-service` reads a
    /// node's configuration, naming no operate listener.
    #[test]
    fn the_starter_slices_and_reads_as_the_service_reads_it() {
        let cluster = xmip_configure::fixture::test_cluster();
        let node = cluster.node(0).name.clone();
        let source = starter(&cluster.name, &node, r"HOST\installer");

        let sliced = xmip_configure::slice(&source, &node).expect("slices");
        let directory = std::env::temp_dir().join(format!("xmip-starter-{}", std::process::id()));
        std::fs::create_dir_all(&directory).expect("a directory");
        let file = directory.join(NODE_FILE);
        let signed = xmip_runtime::signed::signed_beside(&file, &cluster.name, &source, &sliced)
            .expect("signed");
        std::fs::write(&file, signed).expect("written");
        let read = xmip_runtime::start::read(&text(&file));
        std::fs::remove_dir_all(&directory).expect("removed");

        let (document, _, _) = read.expect("reads");
        assert_eq!(document.service.node_name, node);
        assert_eq!(document.service.cluster_name, cluster.name);
        assert!(!document.service.online);
        assert_eq!(
            document.roles.as_deref(),
            Some("storage"),
            "one node stores"
        );
        // The local endpoint starts named as the service is, nothing else
        // listens, and the account that installed operates.
        let operate = document.operate.expect("[operate]");
        assert!(operate.listen.is_none());
        assert_eq!(operate.operators, [r"HOST\installer"]);
        assert!(source.contains(&quoted(&node_service_name(&node))));
    }

    #[test]
    fn a_name_is_quoted_as_toml_says_it() {
        assert_eq!(quoted(r#"a"b\c"#), r#""a\"b\\c""#);
    }
}
