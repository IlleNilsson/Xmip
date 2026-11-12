//! What `xmip-service` opens for a node before it accepts work, as one of
//! the attempt's steps (ADR-0031, amendment 2026-11-12): its publisher, its
//! operate listeners over the board the publisher posts to (ADR-0067), the
//! cluster's authority where the slice the node runs serves it (ADR-0034,
//! amendment 2026-10-22), and the watch on where it takes orders. Each can
//! refuse the attempt, at accept-work, with nothing served: the runtime
//! then makes the same attempt over the node's active configuration
//! (`running::activation::started`). And what the node runs, audited once
//! it is activated (`configured`).

use std::path::{Path, PathBuf};
use std::sync::mpsc::Sender;

use xmip_audit::program_audit::ProgramAudit;
use xmip_core::ExecutionPhase;
use xmip_runtime::directory_watch::DirectoryWatch;
use xmip_runtime::plane::Listener;
use xmip_runtime::running::activation::Standing;
use xmip_runtime::running::{Refusal, Running};
use xmip_runtime::service::StartupPhase;

use crate::audit::{fail, record};
use crate::authority;
use crate::orders;
use crate::publication::{self, Publisher};
use crate::run::Told;

/// What the program holds for a node while it runs.
pub struct Opened<'a> {
    pub publisher: Publisher<'a>,
    /// Its operate listeners, held until the drain.
    pub operate: Vec<Listener>,
    /// Where they listen, in words; none where it has none.
    pub listening: Option<String>,
    /// The cluster's authority it serves, held until the drain.
    pub authority: Option<authority::Served>,
    /// Where it takes orders, and the watch on it.
    pub orders: PathBuf,
    pub watch: DirectoryWatch,
}

/// Open for `running`, an attempt started and serving nothing, the node
/// configured at `configuration`, what the program holds while it runs,
/// telling `tell` of each act and order.
///
/// # Errors
/// What cannot be opened, at accept-work, in words naming it.
pub fn opened<'a>(
    (program, audit): (&'a str, &'a ProgramAudit),
    configuration: &str,
    running: &Running,
    tell: &Sender<Told>,
) -> Result<Opened<'a>, Refusal> {
    let refused = |problem: String| Refusal::at(StartupPhase::AcceptWork, vec![problem]);
    let orders = orders::place(running);
    let place = publication::place(running);
    let publisher = Publisher::new(program, audit, running, place, &orders);
    let board = publisher.board(tell);
    let operate = running.operate(&board, audit).map_err(refused)?;
    let listening = (!operate.is_empty()).then(|| {
        let each: Vec<String> = operate.iter().map(Listener::address).collect();
        each.join(" and ")
    });
    let authority =
        authority::serve(running.provision(), Path::new(configuration)).map_err(refused)?;
    let watch = orders::watch(&orders, &running.location(), tell).map_err(refused)?;
    Ok(Opened {
        publisher,
        operate,
        listening,
        authority,
        orders,
        watch,
    })
}

/// What `running` runs, audited in the runtime's words: a candidate
/// activated as the record of `configuration`, a candidate refused or not
/// kept as its failure; and said on the console.
pub fn configured(program: &str, audit: &ProgramAudit, running: &Running) {
    let Some(standing) = running.standing() else {
        return;
    };
    let location = running.location();
    println!("{program}: {location} configuration: {}", standing.said());
    match standing {
        Standing::Activated { runs, replacing } => {
            let serial = runs.serial.to_string();
            let replaced = replacing.as_ref().map(ToString::to_string);
            record(
                audit,
                "configuration",
                ExecutionPhase::Finished,
                &[
                    ("node", location.as_str()),
                    ("serial", serial.as_str()),
                    ("save", runs.save.as_str()),
                    ("replaced", replaced.as_deref().unwrap_or("")),
                ],
            );
        }
        Standing::Refused { .. } | Standing::Unkept { .. } => {
            fail(
                audit,
                "configuration",
                &format!("{program}: {location} {}", standing.said()),
            );
        }
        Standing::Active { .. } => {}
    }
}
