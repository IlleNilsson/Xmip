//! The orders an operator leaves for the node `xmip-service` runs: a pause
//! or a resume of one of its Subscriptions (ADR-0013, amendment
//! 2026-09-30), a Replay of a Message its Dead Message Queue keeps
//! (ADR-0052, amendment 2026-10-01), and a Retry or Dismiss of a Journey it
//! sends that failed (`runtime-model.md` section 13), taken at each look and
//! applied through
//! the runtime's act, which records it in this process's audit and writes
//! what it leaves to Xmip Storage.
//!
//! They are left in `<data>/orders`, the node's data directory's
//! (`[service] data`), as `observe::Order` writes them; the service declares
//! the place (ADR-0053), so whoever finds the process finds where it takes
//! orders. Each is applied by the runtime's one apply (`applied::apply`),
//! which an act reaching the node's operate listener goes through too: this
//! node keeps no Event subscription hub, so an order for an Event
//! subscription is refused in words, as is any order the runtime refuses;
//! each refusal is audited as the failure to `order`.

use std::path::{Path, PathBuf};
use std::time::Duration;

use xmip_audit::program_audit::ProgramAudit;
use xmip_observe::Order;
use xmip_runtime::applied::apply;
use xmip_runtime::running::Running;

use crate::run;

/// How long the service waits between looks for an order, and for a stop.
/// A look reads one directory; an order is applied within this of being
/// left.
pub const LOOK: Duration = Duration::from_millis(10);

/// Where the node takes its orders, beneath its data directory.
pub fn place(running: &Running) -> PathBuf {
    running.data().join("orders")
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
