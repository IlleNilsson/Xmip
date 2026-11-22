//! `--install` and `--uninstall`: what a package runs to lay a node out and
//! register its Xmip Service, and to remove the service again (ADR-0015,
//! amendment 2026-10-13). Every package — the MSI, the `.deb` and `.rpm`,
//! the macOS `.pkg` — and a person unpacking the portable archive run these
//! two, so the layout, the starter and the registration are written here
//! once and in no package's own script.
//!
//! `--install`, with `cluster.xmip` at `--configuration`:
//!
//! 1. writes a starter `cluster.xmip` there, where there is none: the cluster
//!    `--cluster` names, the node `--node` names, declaring the storage
//!    role, for one node keeps Xmip Storage itself (ADR-0056, amendment
//!    2026-10-20), offline (ADR-0045); its
//!    local operate endpoint needs no line, for it always starts, named
//!    `xmip-<node>` as its service is (ADR-0014, amendments 2026-10-13),
//!    and the account that installs is its one operator (ADR-0009,
//!    amendment 2026-11-07);
//! 2. slices the node's configuration, `node.xmip` beside it, where
//!    there is none — `xmip-core-configure`'s one slicing, as the cluster
//!    `--cluster` names where the cluster's file names none (ADR-0028,
//!    amendment 2026-10-21);
//! 3. makes the layout's `modules` and `logs` beside `config`, the node's
//!    data directory and the audit directory under it (ADR-0015 clause 10);
//! 4. registers the node's Xmip Service — `definition.rs`'s, which
//!    `--definition` prints — through the runtime's one registration of a
//!    service (`registration::apply`) to start with the machine, as the account
//!    `--account` names where it is given, which is given what the node
//!    reads and writes (`account.rs`), and starts it;
//! 5. writes the command line's `cli.toml` beside the programs, where there
//!    is none, stating that node at its local endpoint (`command_line.rs`).
//!
//! A configuration already there is the operator's and is never written
//! over. `--uninstall`, with the node's configuration at `--configuration`
//! as `--definition` takes it, stops that node's service, waiting for its
//! drain, and removes it; it deletes no configuration, `cli.toml` among it,
//! no data and no audit (ADR-0040). Both
//! need the elevation registering needs (ADR-0018, Open): a package
//! installs elevated, and a person without it is refused in the service
//! manager's words.

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use xmip_audit::audit_store::DIRECTORY_VARIABLE;
use xmip_audit::program_audit::ProgramAudit;
use xmip_core::ExecutionPhase;
use xmip_runtime::registration::{REFUSED, ServiceDefinition, apply, node_service_name};

use crate::account::{self, Given};
use crate::arguments::Arguments;
use crate::audit;
use crate::command_line;
use crate::definition::{self, text};
use crate::starter::starter;

/// The node's configuration, sliced beside its cluster's `cluster.xmip`.
pub const NODE_FILE: &str = "node.xmip";

/// The installed layout's folders beside `config` that nothing else makes
/// (ADR-0015 clause 10): `data` is the node configuration's to say, and
/// `bin` the package's.
const LAYOUT: [&str; 2] = ["modules", "logs"];

/// Install, or refuse in words.
pub fn install(audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    ended(audit, "install", installed(audit, arguments))
}

/// Uninstall, or refuse in words.
pub fn uninstall(audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    ended(audit, "uninstall", uninstalled(audit, arguments))
}

fn ended(audit: &ProgramAudit, action: &str, outcome: Result<String, String>) -> ExitCode {
    match outcome {
        Ok(said) => {
            println!("OK: {said}");
            audit::record(audit, action, ExecutionPhase::Finished, &[("said", &said)]);
            ExitCode::SUCCESS
        }
        Err(problem) => {
            audit::fail(audit, action, &format!("xmip-service: {problem}"));
            ExitCode::from(REFUSED)
        }
    }
}

fn installed(audit: &ProgramAudit, arguments: &Arguments) -> Result<String, String> {
    let (node, cluster) = match (&arguments.node, &arguments.cluster) {
        (Some(node), Some(cluster)) => (node.as_str(), cluster.as_str()),
        _ => return Err("--install needs --node and --cluster".to_string()),
    };
    let cluster_file = PathBuf::from(&arguments.configuration);
    let directory = cluster_file
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .to_path_buf();
    audit::record(audit, "install", ExecutionPhase::Begin, &[("node", node)]);
    std::fs::create_dir_all(&directory).map_err(|error| said(&directory, &error))?;

    let node_file = directory.join(NODE_FILE);
    // A node given its slice, signed where the environment is deployed from,
    // is laid out by it alone: no cluster's file is written beside it
    // (ADR-0031, amendment 2026-11-06).
    if !node_file.exists() {
        if !cluster_file.exists() {
            // Whoever installs operates the node: a caller no list names
            // holds no role (ADR-0009, amendment 2026-11-07).
            let operator = xmip_runtime::plane::local::running_as()?;
            write(&cluster_file, &starter(cluster, node, &operator))?;
        }
        let source =
            std::fs::read_to_string(&cluster_file).map_err(|error| said(&cluster_file, &error))?;
        let sliced = if xmip_configure::cluster::cluster_name(&source)?.is_some() {
            xmip_configure::slice(&source, node)?
        } else {
            xmip_configure::slice_named(&source, node, cluster)?
        };
        let signed = xmip_runtime::signed::signed_beside(&node_file, cluster, &source, &sliced)?;
        write(&node_file, &signed)?;
    }

    if let Some(root) = directory.parent() {
        for folder in LAYOUT {
            let folder = root.join(folder);
            std::fs::create_dir_all(&folder).map_err(|error| said(&folder, &error))?;
        }
    }
    let (configured, mut service) = definition::node_service(&node_file)?;
    let mut given = Vec::new();
    if let Some(account) = &arguments.account {
        service = service.running_as(account);
        given = account::given(&node_file)?;
    }
    for (name, value) in &service.environment {
        if name == DIRECTORY_VARIABLE {
            std::fs::create_dir_all(value).map_err(|error| said(Path::new(value), &error))?;
        }
    }
    apply::register(&service, &configured, &|| give(&service, &given))?;
    let followed = command_line::place(&service)?;
    Ok(format!(
        "{} registered and started, configured by {}{followed}",
        service.name,
        text(&node_file)
    ))
}

fn uninstalled(audit: &ProgramAudit, arguments: &Arguments) -> Result<String, String> {
    let (document, _, _) =
        xmip_runtime::start::read(&arguments.configuration).map_err(|unread| unread.reason)?;
    let node = document.service.node_name;
    let name = node_service_name(&node);
    audit::record(
        audit,
        "uninstall",
        ExecutionPhase::Begin,
        &[("service", &name)],
    );
    apply::deregister(&name, &node)
}

fn write(path: &Path, content: &str) -> Result<(), String> {
    std::fs::write(path, content).map_err(|error| said(path, &error))
}

fn said(path: &Path, error: &std::io::Error) -> String {
    format!("{}: {error}", path.display())
}

/// The account `service` runs as given each of `given`; nothing where it
/// runs as the platform's default.
fn give(service: &ServiceDefinition, given: &[Given]) -> Result<(), String> {
    match &service.service_identity {
        Some(account) => account::give(account, given),
        None => Ok(()),
    }
}
