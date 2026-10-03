//! `--slice`: the node's configuration, sliced from its cluster's
//! `xmip.toml` by `xmip-core-configure`'s one slicing (ADR-0031, amendment
//! 2026-10-03: *When deployed the sections regarding a node will be sliced
//! to that node*). Desired state runs it on each node it deploys and writes
//! what it prints where the node reads its configuration
//! (`deployment-model.md` section 8); nothing here writes a file.

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
    let cluster = std::fs::read_to_string(&arguments.configuration)
        .map_err(|error| format!("cannot read {}: {error}", arguments.configuration))?;
    xmip_configure::slice(&cluster, node)
}
