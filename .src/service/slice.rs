//! `--slice`: the node's configuration, sliced from its cluster's
//! `cluster.xmip` by `xmip-core-configure`'s one slicing (ADR-0031, amendment
//! 2026-10-03: *When deployed the sections regarding a node will be sliced
//! to that node*). Desired state runs it on each node it deploys and writes
//! what it prints where the node reads its configuration
//! (`deployment-model.md` section 8). What it prints is signed by the
//! cluster's authority kept in `--authority`, the machine deploying the
//! environment's, or beside the cluster's file where it names none, made there
//! where none is (`signed::sliced_signed`, the one slicing and signing
//! `xmip_cluster_signed_slice_v1` asks too; ADR-0031, amendments 2026-11-06
//! and 2026-11-19); nothing else is written. With
//! `--cluster`, a cluster's file that names no cluster is sliced as that
//! one, and one naming another is refused (`slice_named`; ADR-0028,
//! amendment 2026-10-21). With `--bind`, each Receive Location and Send
//! Port the file designs is placed on one of the environment's `--nodes`
//! and each Work Process on every one serving its stage, refusing work no
//! node satisfies, the Locations bound first over the Parties' far ends,
//! each the far end of its turn, and with `--listen` each Receive Location
//! listening on its node (`placed::at_far_ends`; ADR-0028, amendments
//! 2026-10-22 and 2026-11-22; ADR-0056, amendment 2026-11-13), and the
//! node's own placements are in its slice.
//! With `--operators`, each name is listed among the node's `[operate]
//! operators`: on machines of their own the environment names who operates
//! its nodes (`observers::operated_by`).

use std::process::ExitCode;

use xmip_audit::program_audit::ProgramAudit;
use xmip_runtime::registration::REFUSED;

use crate::arguments::Arguments;
use crate::audit;

/// Print the slice, or refuse in words.
pub fn print(audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    match sliced(arguments) {
        Ok(text) => {
            print!("{text}");
            ExitCode::SUCCESS
        }
        Err(problem) => {
            audit::fail(audit, "slice", &format!("xmip-service: {problem}"));
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
    if !arguments.bind.is_empty() {
        cluster = xmip_configure::placed::at_far_ends(
            &cluster,
            &arguments.nodes,
            &arguments.bind,
            arguments.listen,
        )?;
    }
    cluster = xmip_configure::observers::operated_by(&cluster, &arguments.operators)?;
    xmip_runtime::signed::sliced_signed(
        &cluster,
        std::path::Path::new(&arguments.configuration),
        node,
        arguments.cluster.as_deref(),
        arguments.authority.as_deref().map(std::path::Path::new),
    )
}
