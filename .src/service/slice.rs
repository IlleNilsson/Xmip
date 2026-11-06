//! `--slice`: the node's configuration, sliced from its cluster's
//! `cluster.xmip` by `xmip-core-configure`'s one slicing (ADR-0031, amendment
//! 2026-10-03: *When deployed the sections regarding a node will be sliced
//! to that node*). Desired state runs it on each node it deploys and writes
//! what it prints where the node reads its configuration
//! (`deployment-model.md` section 8). What it prints is signed by the
//! cluster's authority kept beside the cluster's file, made there where none
//! is (`signed::signed_beside`; ADR-0031, amendment 2026-11-06); nothing
//! else is written. With
//! `--cluster`, a cluster's file that names no cluster is sliced as that
//! one, and one naming another is refused (`slice_named`; ADR-0028,
//! amendment 2026-10-21). With `--bind`, each Receive Location and Send
//! Port the file designs is placed on the environment's `--nodes` over SFTP
//! on the Parties' far end first (`placed::at_far_end`; ADR-0028, amendment
//! 2026-10-22), and the node's own placements are in its slice.

use std::process::ExitCode;

use xmip_audit::program_audit::ProgramAudit;
use xmip_runtime::registration::REFUSED;

use crate::arguments::Arguments;
use crate::run;

/// Print the slice, or refuse in words.
pub fn print(audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    match sliced(arguments) {
        Ok(text) => {
            print!("{text}");
            ExitCode::SUCCESS
        }
        Err(problem) => {
            run::fail(audit, "slice", &format!("xmip-service: {problem}"));
            ExitCode::from(REFUSED)
        }
    }
}

fn sliced(arguments: &Arguments) -> Result<String, String> {
    let node = arguments
        .node
        .as_deref()
        .ok_or("--slice needs --node, the node it slices for")?;
    let mut cluster = std::fs::read_to_string(&arguments.configuration)
        .map_err(|error| format!("cannot read {}: {error}", arguments.configuration))?;
    if let Some(host) = arguments.bind.as_deref() {
        cluster = xmip_configure::placed::at_far_end(&cluster, &arguments.nodes, host)?;
    }
    let (sliced, name) = match arguments.cluster.as_deref() {
        Some(name) => (
            xmip_configure::slice_named(&cluster, node, name)?,
            name.to_string(),
        ),
        None => (
            xmip_configure::slice(&cluster, node)?,
            xmip_configure::cluster::cluster_name(&cluster)?.unwrap_or_default(),
        ),
    };
    let configuration = std::path::Path::new(&arguments.configuration);
    xmip_runtime::signed::signed_beside(configuration, &name, &cluster, &sliced)
}
