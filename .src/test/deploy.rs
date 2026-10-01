//! Every node configuration `deploy/` writes — the Ansible role's template
//! and the file the DSC document's script writes — rendered with
//! representative values and read the way `xmip-service` reads its own:
//! `xmip_runtime::start::read`, then the execution tree against the
//! technologies the runtime carries. The reader keeps no key it does not
//! know, so each rendered key must also come back when the document the
//! reader made of it is written out: a template in an older shape (`[node]`,
//! `[storage]`) or naming a key the reader drops fails here, not on an
//! installed node.
//!
//! No Jinja2 runs in the estate's tests, so the template is rendered by
//! [`render`], which takes exactly what the template uses and refuses the
//! rest by name: a template that outgrows it fails rather than rendering
//! wrong.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use xmip_configure::XmipConfigurationDocument;
use xmip_runtime::catalogue;
use xmip_runtime::execution_tree::build_execution_tree;

const TEMPLATE: &str = "deploy/ansible/roles/xmip_node/templates/xmip-node.toml.j2";
const DEFAULTS: &str = "deploy/ansible/roles/xmip_node/defaults/main.yml";
const DSC: &str = "deploy/dsc/xmip-node.dsc.yaml";

type Variables = BTreeMap<String, String>;

fn source(relative: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(relative);
    std::fs::read_to_string(&path).unwrap_or_else(|error| panic!("{relative}: {error}"))
}

/// The role's defaults: every top-level `name: value` with a scalar value.
fn defaults() -> Variables {
    source(DEFAULTS)
        .lines()
        .filter(|line| !line.starts_with([' ', '#', '-']))
        .filter_map(|line| line.split_once(':'))
        .map(|(name, value)| (name.trim(), value.trim().trim_matches(['"', '\''])))
        .filter(|(_, value)| !value.is_empty())
        .map(|(name, value)| (name.to_string(), value.to_string()))
        .collect()
}

/// Jinja2 as far as the template uses it: `{{ name }}` and a `lower` filter.
/// A statement, a comment, another filter or a name no variable holds panics,
/// naming it.
fn render(template: &str, variables: &Variables) -> String {
    for construct in ["{%", "{#"] {
        assert!(
            !template.contains(construct),
            "{TEMPLATE} uses {construct}, which this test does not render; extend render"
        );
    }
    let mut rendered = String::new();
    let mut rest = template;
    while let Some(open) = rest.find("{{") {
        rendered.push_str(&rest[..open]);
        let after = &rest[open + 2..];
        let close = after.find("}}").expect("every {{ closes");
        let mut parts = after[..close].split('|').map(str::trim);
        let name = parts.next().unwrap_or_default();
        let mut value = variables
            .get(name)
            .unwrap_or_else(|| panic!("{TEMPLATE} names {name}, which no variable holds"))
            .clone();
        for filter in parts {
            assert_eq!(
                filter, "lower",
                "{TEMPLATE} filters by {filter}; extend render"
            );
            value = value.to_lowercase();
        }
        rendered.push_str(&value);
        rest = &after[close + 2..];
    }
    rendered.push_str(rest);
    rendered
}

/// The text between the DSC script's `@'` and `'@`, as PowerShell writes it:
/// without the indentation the YAML block gives it.
fn dsc_configuration() -> String {
    let text = source(DSC);
    let mut lines = text.lines();
    let open = lines
        .by_ref()
        .find(|line| line.trim() == "@'")
        .expect("the DSC script writes its configuration from a here-string");
    let indent = &open[..open.len() - open.trim_start().len()];
    let mut configuration = String::new();
    for line in lines.take_while(|line| !line.trim_start().starts_with("'@")) {
        let line = line
            .strip_prefix(indent)
            .or_else(|| line.trim().is_empty().then_some(""))
            .unwrap_or_else(|| panic!("{DSC}: '{line}' is outside the here-string's indent"));
        configuration.push_str(line);
        configuration.push('\n');
    }
    configuration
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
    let template = source(TEMPLATE);

    let variables = defaults();
    let installed = read(&directory, "ansible", &render(&template, &variables));
    assert_eq!(installed.service.node_name, variables["xmip_node_name"]);
    assert!(!installed.service.online, "ADR-0045: offline unless said");

    let mut given = variables.clone();
    for (name, value) in [
        ("xmip_service_name", "xmip-R1"),
        ("xmip_cluster_name", "C1"),
        ("xmip_node_name", "R1"),
        ("xmip_online", "True"),
    ] {
        given.insert(name.to_string(), value.to_string());
    }
    let node = read(&directory, "ansible-R1", &render(&template, &given));
    assert_eq!(
        (
            node.service.name.as_str(),
            node.service.cluster_name.as_str(),
            node.service.node_name.as_str(),
            node.service.online,
        ),
        ("xmip-R1", "C1", "R1", true),
        "each variable lands on the key it names"
    );

    let sample = read(&directory, "dsc", &dsc_configuration());
    assert!(!sample.service.online, "ADR-0045: offline unless said");

    std::fs::remove_dir_all(&directory).expect("removes what it wrote");
}
