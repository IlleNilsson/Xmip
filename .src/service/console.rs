//! The stop that arrives as a signal: Ctrl+C in a console on every platform
//! (and Ctrl+Break on Windows), SIGTERM and SIGHUP on Linux and macOS — the
//! way systemd and launchd stop a service. Each is the same drain.

use std::process::ExitCode;
use std::sync::mpsc;

use xmip_audit::program_audit::ProgramAudit;

use crate::arguments::{Arguments, Mode};
use crate::readiness;
use crate::run::{self, StoppedBy};

/// Run the node until a signal stops it.
pub fn run(program: &str, audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    let by: StoppedBy = if arguments.mode == Mode::Console {
        "the console"
    } else {
        "the service manager"
    };
    let (stop, stops) = mpsc::channel();
    // Taken before the node starts, so a stop during the start is not lost:
    // it waits in the channel and the node drains as soon as it serves.
    if let Err(error) = ctrlc::set_handler(move || {
        let _ = stop.send(by);
    }) {
        run::fail(
            audit,
            "start",
            &format!("{program}: cannot take the stop signal: {error}"),
        );
        return ExitCode::from(xmip_runtime::registration::REFUSED);
    }
    if arguments.mode == Mode::Console {
        println!("{program}: Ctrl+C stops the node");
    }

    run::serve(
        program,
        audit,
        arguments,
        &stops,
        readiness::ready,
        readiness::stopping,
    )
    .code()
}
