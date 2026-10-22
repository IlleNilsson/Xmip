//! The stop that arrives as a signal: Ctrl+C in a console on every platform
//! (and Ctrl+Break on Windows), SIGTERM and SIGHUP on Linux and macOS — the
//! way systemd and launchd stop a service — and, for a node a test started,
//! the end of its input. Each is the same drain.

use std::process::ExitCode;
use std::sync::mpsc;

use xmip_audit::program_audit::ProgramAudit;
use xmip_node::Purpose;

use crate::arguments::{Arguments, Mode};
use crate::readiness;
use crate::run::{self, StoppedBy, Told};

/// Run the node until a signal stops it.
pub fn run(program: &str, audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    let by: StoppedBy = if arguments.mode == Mode::Console {
        "the console"
    } else {
        "the service manager"
    };
    let (tell, told) = mpsc::channel();
    // Taken before the node starts, so a stop during the start is not lost:
    // it waits in the channel and the node drains as soon as it serves.
    let stop = tell.clone();
    if let Err(error) = ctrlc::set_handler(move || {
        let _ = stop.send(Told::Stop(by));
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
    // A test's rig, which has no console of its own to press Ctrl+Break
    // in, stops the node it started by ending its input: the same drain.
    if arguments.mode == Mode::Console && arguments.purpose == Purpose::Test {
        let ended = tell.clone();
        std::thread::spawn(move || {
            let _ = std::io::copy(&mut std::io::stdin().lock(), &mut std::io::sink());
            let _ = ended.send(Told::Stop("its input ending"));
        });
        println!("{program}: the end of its input stops the node, as its test ends it");
    }

    run::serve(
        program,
        audit,
        arguments,
        (&tell, &told),
        readiness::ready,
        readiness::stopping,
    )
    .code()
}
