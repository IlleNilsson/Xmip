//! `--readiness`: whether the node configured at `<path>` is ready — it runs
//! the slice there and its Xmip Storage stands Fine — said in the node's own
//! words, exit 0 where it is and the refused code where it is not (ADR-0056,
//! amendment 2026-11-23). With `--within <seconds>` it is asked again each
//! time the node publishes ([`EVERY`]) until the node is ready, or the bound
//! is spent and it is refused in words naming it. A deployment asks it after
//! it restarts a node, before it restarts the next, so a Storage node is
//! never stopped while the one restarted before it could not take over. The
//! rule and the words are the runtime's (`running::activation::readiness`);
//! this only asks, and waits, counting on the operating system's Clock.

use std::process::ExitCode;

use xmip_audit::program_audit::ProgramAudit;
use xmip_core::clock::between;
use xmip_core::{Clock, SystemClock};
use xmip_runtime::registration::REFUSED;

use crate::arguments::Arguments;
use crate::audit;
use crate::publication::EVERY;

/// Say whether the node is ready, waiting for it `--within` where given.
pub fn print(audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    let path = &arguments.configuration;
    let began = SystemClock.monotonic_nanos();
    let said = loop {
        match xmip_runtime::running::activation::readiness(path) {
            Ok(said) => {
                println!("{said}");
                return ExitCode::SUCCESS;
            }
            Err(said) => {
                let spent = between(began, SystemClock.monotonic_nanos());
                match arguments.within {
                    Some(within) if spent < within => {
                        std::thread::sleep(EVERY.min(within.saturating_sub(spent)));
                    }
                    _ => break said,
                }
            }
        }
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
