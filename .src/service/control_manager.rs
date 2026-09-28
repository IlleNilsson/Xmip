//! `xmip-service` under the Windows Service Control Manager: the dispatcher
//! the manager starts it through, the control handler its Stop and Shutdown
//! arrive on, and the states it reports — start pending while ADR-0018's
//! phases run, running once the node accepts work, stop pending while it
//! drains, stopped with the exit code.
//!
//! The handler only says a stop arrived; the drain is `run::serve`'s, the
//! same one a console's Ctrl+C and a Unix SIGTERM reach. The service is its
//! own process, so the name the dispatcher and the handler are given is not
//! looked up; the service is registered under `registration`'s name.

use std::process::ExitCode;
use std::sync::OnceLock;
use std::sync::mpsc::{self, Sender};
use std::time::Duration;

use windows_service::service::{
    ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus, ServiceType,
};
use windows_service::service_control_handler::{self, ServiceControlHandlerResult};
use windows_service::service_dispatcher;
use xmip_audit::program_audit::ProgramAudit;
use xmip_runtime::registration::REFUSED;

use crate::PROGRAM;
use crate::arguments::Arguments;
use crate::run::{self, Ended, StoppedBy};

/// What the process was told, for the service's main, which the dispatcher
/// calls with nothing of it.
struct Told {
    program: String,
    audit: ProgramAudit,
    arguments: Arguments,
}

static TOLD: OnceLock<Told> = OnceLock::new();
static ENDED: OnceLock<u8> = OnceLock::new();

/// How long the manager is told a start or a drain may take before it
/// hears again; the node's own waits bound both.
const WAIT: Duration = Duration::from_secs(30);

/// Hand the process to the Service Control Manager, which calls the
/// service's main and returns when the service has stopped.
pub fn run(program: String, audit: ProgramAudit, arguments: Arguments) -> ExitCode {
    let _ = TOLD.set(Told {
        program,
        audit,
        arguments,
    });
    match service_dispatcher::start(PROGRAM, service_main) {
        Ok(()) => ExitCode::from(ENDED.get().copied().unwrap_or(0)),
        Err(error) => {
            if let Some(told) = TOLD.get() {
                run::fail(
                    &told.audit,
                    "start",
                    &format!(
                        "{}: the Service Control Manager did not start it ({error}); \
                         --console runs it in a terminal",
                        told.program
                    ),
                );
            }
            ExitCode::from(REFUSED)
        }
    }
}

/// The service's main, as the dispatcher calls it. The arguments a start
/// passes are not read: the node is the one `--configuration` named.
extern "system" fn service_main(_count: u32, _arguments: *mut *mut u16) {
    if let Some(told) = TOLD.get() {
        serve(told);
    }
}

fn serve(told: &Told) {
    let (stop, stops) = mpsc::channel();
    let registered =
        service_control_handler::register(PROGRAM, move |control| answer(control, &stop));
    let status = match registered {
        Ok(status) => status,
        Err(error) => {
            let problem = format!(
                "{}: cannot take the manager's controls: {error}",
                told.program
            );
            run::fail(&told.audit, "start", &problem);
            let _ = ENDED.set(REFUSED);
            return;
        }
    };
    let report = |state: ServiceState, accepted: ServiceControlAccept, code: u8| {
        let reported = status.set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: state,
            controls_accepted: accepted,
            exit_code: if code == 0 {
                ServiceExitCode::Win32(0)
            } else {
                ServiceExitCode::ServiceSpecific(u32::from(code))
            },
            checkpoint: 0,
            wait_hint: WAIT,
            process_id: None,
        });
        if let Err(error) = reported {
            eprintln!("{}: could not report {state:?}: {error}", told.program);
        }
    };
    let taken = ServiceControlAccept::STOP | ServiceControlAccept::SHUTDOWN;

    report(ServiceState::StartPending, ServiceControlAccept::empty(), 0);
    let ended = run::serve(
        &told.program,
        &told.audit,
        &told.arguments,
        &stops,
        || report(ServiceState::Running, taken, 0),
        || report(ServiceState::StopPending, ServiceControlAccept::empty(), 0),
    );
    let code = match ended {
        Ended::Stopped => 0,
        Ended::Refused => REFUSED,
    };
    let _ = ENDED.set(code);
    report(ServiceState::Stopped, ServiceControlAccept::empty(), code);
}

/// The manager's control, answered: a Stop or a Shutdown is the drain,
/// asked; an Interrogate is answered by the last status; nothing else is
/// taken.
fn answer(control: ServiceControl, stop: &Sender<StoppedBy>) -> ServiceControlHandlerResult {
    let by: StoppedBy = match control {
        ServiceControl::Stop => "the Service Control Manager",
        ServiceControl::Shutdown => "the system shutting down",
        ServiceControl::Interrogate => return ServiceControlHandlerResult::NoError,
        _ => return ServiceControlHandlerResult::NotImplemented,
    };
    // The receiver is gone only once the node has drained; a stop then asks
    // for nothing.
    let _ = stop.send(by);
    ServiceControlHandlerResult::NoError
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_stop_and_a_shutdown_each_ask_for_the_drain_once() {
        let (stop, stops) = mpsc::channel();

        for (control, by) in [
            (ServiceControl::Stop, "the Service Control Manager"),
            (ServiceControl::Shutdown, "the system shutting down"),
        ] {
            assert!(matches!(
                answer(control, &stop),
                ServiceControlHandlerResult::NoError
            ));
            assert_eq!(stops.try_recv(), Ok(by));
        }
        assert!(stops.try_recv().is_err(), "one stop per control");
    }

    #[test]
    fn nothing_else_the_manager_sends_stops_the_node() {
        let (stop, stops) = mpsc::channel();

        assert!(matches!(
            answer(ServiceControl::Interrogate, &stop),
            ServiceControlHandlerResult::NoError
        ));
        assert!(matches!(
            answer(ServiceControl::Pause, &stop),
            ServiceControlHandlerResult::NotImplemented
        ));
        assert!(stops.try_recv().is_err());
    }

    #[test]
    fn a_stop_after_the_drain_asks_for_nothing() {
        let (stop, stops) = mpsc::channel();
        drop(stops);

        assert!(matches!(
            answer(ServiceControl::Stop, &stop),
            ServiceControlHandlerResult::NoError
        ));
    }
}
