//! `--activation`: whether the node configured at `<path>` runs the slice
//! there as its active configuration, said in the node's own words, exit 0
//! where it does and the refused code where it does not (ADR-0031,
//! amendment 2026-11-12). A deployment asks it after it restarts a node: a
//! correctly signed slice the node cannot start is refused and the node
//! runs its active configuration, so a started service alone does not say
//! the slice took. The rule and the words are the runtime's
//! (`running::activation::activation`, over the node's publication); this
//! only asks.

use std::process::ExitCode;

use xmip_audit::program_audit::ProgramAudit;
use xmip_runtime::registration::REFUSED;

use crate::arguments::Arguments;
use crate::audit;

/// Say what the node runs, or why not the slice at `--configuration`.
pub fn print(audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    match xmip_runtime::running::activation::activation(&arguments.configuration) {
        Ok(said) => {
            println!("{said}");
            ExitCode::SUCCESS
        }
        Err(said) => {
            audit::fail(audit, "activation", &format!("xmip-service: {said}"));
            ExitCode::from(REFUSED)
        }
    }
}
