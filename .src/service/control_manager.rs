//! `xmip-service` under the Windows Service Control Manager, through the
//! runtime's one dispatcher (`registration::control_manager`): start pending
//! while ADR-0018's phases run, running once the node accepts work, stop
//! pending while it drains, stopped with the exit code.
//!
//! A Stop or a Shutdown the manager sends is the drain, asked: `run::serve`'s,
//! the same one a console's Ctrl+C and a Unix SIGTERM reach. The service is
//! its own process, so the name the dispatcher is given is not looked up; the
//! service is registered under `registration`'s name.

use std::process::ExitCode;
use std::sync::mpsc;

use xmip_audit::program_audit::ProgramAudit;
use xmip_runtime::registration::REFUSED;
use xmip_runtime::registration::control_manager::{self, Reporter};

use crate::arguments::Arguments;
use crate::run::{self, Ended};
use crate::{PROGRAM, audit};

/// Hand the process to the Service Control Manager, which runs the node and
/// returns when it has stopped.
pub fn run(program: String, audit: ProgramAudit, arguments: Arguments) -> ExitCode {
    let (tell, stops) = mpsc::channel();
    let stop = tell.clone();
    let refused = (program.clone(), audit.clone());
    let serving = Box::new(move |reporter: &Reporter| {
        let ended = run::serve(
            &program,
            &audit,
            &arguments,
            (&tell, &stops),
            || reporter.running(),
            || reporter.stopping(),
        );
        match ended {
            Ended::Stopped => 0,
            Ended::Refused => REFUSED,
        }
    });
    // The receiver is gone only once the node has drained; a stop then asks
    // for nothing.
    let stopping = Box::new(move |by: &'static str| {
        let _ = stop.send(run::Told::Stop(by));
    });
    match control_manager::run(PROGRAM, stopping, serving) {
        Ok(code) => ExitCode::from(code),
        Err(problem) => {
            let (program, audit) = refused;
            audit::fail(
                &audit,
                "start",
                &format!("{program}: {problem}; --console runs it in a terminal"),
            );
            ExitCode::from(REFUSED)
        }
    }
}
