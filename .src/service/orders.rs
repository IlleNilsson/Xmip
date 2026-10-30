//! The orders an operator leaves for the node `xmip-service` runs: a pause
//! or a resume of one of its Subscriptions (ADR-0013, amendment
//! 2026-09-30), a Replay of a Message its Dead Message Queue keeps
//! (ADR-0052, amendment 2026-10-01), and a Retry or Dismiss of a Message it
//! sends that failed (`runtime-model.md` section 13), taken the moment the
//! operating system says one was left and applied through the runtime's
//! act, which records it in this process's audit and writes what it leaves
//! to Xmip Storage.
//!
//! They are left in `<data>/orders`, the node's data directory's
//! (`[service] data`), as `observe::Order` writes them; the service declares
//! the place (ADR-0053), so whoever finds the process finds where it takes
//! orders. The node's own directory there is watched
//! (`xmip_runtime::directory_watch`): the service waits in the kernel and
//! is told each time a file is renamed into it (on Windows each time a name
//! there changes), never looking again and again.
//! Each is applied by the runtime's one apply (`applied::apply`),
//! which an act reaching the node's operate listener goes through too: this
//! node keeps no Event subscription hub, so an order for an Event
//! subscription is refused in words, as is any order the runtime refuses;
//! each refusal is audited as the failure to `order`.

use std::path::{Path, PathBuf};
use std::sync::mpsc::Sender;

use xmip_audit::program_audit::ProgramAudit;
use xmip_observe::Order;
use xmip_runtime::applied::apply;
use xmip_runtime::directory_watch::DirectoryWatch;
use xmip_runtime::running::Running;

use crate::run::{self, Told};

/// Where the node takes its orders, beneath its data directory.
pub fn place(running: &Running) -> PathBuf {
    running.data().join("orders")
}

/// Watch where the orders for the node at `node` lie in `orders`, made if
/// it is not there, and tell `tell` of each change while the watch is held.
///
/// # Errors
///
/// The sentence that says why the place cannot be watched.
pub fn watch(orders: &Path, node: &str, tell: &Sender<Told>) -> Result<DirectoryWatch, String> {
    let place = Order::place(orders, node)?;
    std::fs::create_dir_all(&place)
        .map_err(|error| format!("cannot make {}: {error}", place.display()))?;
    let tell = tell.clone();
    DirectoryWatch::spawn(&place, move || {
        let _ = tell.send(Told::Orders);
    })
    .map_err(|error| format!("cannot watch {}: {error}", place.display()))
}

/// Take every order left for the node at `node` in `orders`, oldest first,
/// and apply each; how many were applied.
pub fn take(program: &str, audit: &ProgramAudit, orders: &Path, node: &str) -> usize {
    let mut applied_count = 0;
    for taken in Order::take(orders, node) {
        let applied = taken
            .map_err(|problem| format!("an order no node can take: {problem}"))
            .and_then(|order| apply(&order).into_result());
        match applied {
            Ok(said) => {
                applied_count += 1;
                println!("{program}: {said}");
            }
            Err(problem) => run::fail(audit, "order", &format!("{program}: {problem}")),
        }
    }
    applied_count
}
