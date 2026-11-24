//! `--readiness`: whether the node configured at `<path>` is ready — it runs
//! the slice there and its Xmip Storage stands Fine, by what it published
//! since its start now — said in the node's own words, exit 0 where it is
//! and the refused code where it is not (ADR-0056, amendments 2026-11-23 and
//! 2026-11-24). With `--within <seconds>` it is told each time the node
//! publishes, the operating system saying the folder it publishes in
//! changed, until the node is ready, or the bound is spent and it is refused
//! in words naming it; never a sleep. A deployment asks it after it restarts
//! a node, before it restarts the next, so a Storage node is never stopped
//! while the one restarted before it could not take over. The rule, the
//! wait and the words are the runtime's
//! (`running::activation::readiness`, `awaited`); this only asks, counting
//! on the operating system's Clock.

use std::process::ExitCode;

use xmip_audit::program_audit::ProgramAudit;
use xmip_core::SystemClock;
use xmip_runtime::registration::REFUSED;
use xmip_runtime::running::activation::{awaited, readiness};

use crate::arguments::Arguments;
use crate::audit;

/// Say whether the node is ready, waiting for it `--within` where given.
pub fn print(audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    let path = &arguments.configuration;
    let asked = match arguments.within {
        Some(within) => awaited(path, within, &SystemClock),
        None => readiness(path),
    };
    let said = match asked {
        Ok(said) => {
            println!("{said}");
            return ExitCode::SUCCESS;
        }
        Err(said) => said,
    };
    let bound = arguments.within.map_or_else(String::new, |within| {
        format!(" within {} s", within.as_secs())
    });
    audit::fail(
        audit,
        "readiness",
        &format!("xmip-service: REFUSED{bound}: {said}"),
    );
    ExitCode::from(REFUSED)
}
