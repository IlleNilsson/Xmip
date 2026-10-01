//! The orders an operator leaves for the node `xmip-service` runs: a pause
//! or a resume of one of its Subscriptions (ADR-0013, amendment
//! 2026-09-30), taken at each look and applied through the runtime's act,
//! which records it in this process's audit and keeps what it leaves in the
//! node's runtime store.
//!
//! They are left in `<data>/orders`, the node's data directory's
//! (`[service] data`), as `observe::Order` writes them; the service declares
//! the place (ADR-0053), so whoever finds the process finds where it takes
//! orders. This node keeps no Event subscription hub, so an order for an
//! Event subscription is refused in words, as is any order the runtime
//! refuses; each refusal is audited as the failure to `order`.

use std::path::{Path, PathBuf};
use std::time::Duration;

use xmip_audit::program_audit::ProgramAudit;
use xmip_observe::{Noun, Order};
use xmip_runtime::running::Running;

use crate::run;

/// How long the service waits between looks for an order, and for a stop.
/// A look reads one directory; an order is applied within this of being
/// left.
pub const LOOK: Duration = Duration::from_millis(10);

/// Where the node takes its orders, beneath its data directory.
pub fn place(running: &Running) -> PathBuf {
    running.store().data().join("orders")
}

/// Take every order left for the node at `node` in `orders`, oldest first,
/// and apply each; how many were applied.
pub fn take(
    program: &str,
    audit: &ProgramAudit,
    running: &Running,
    orders: &Path,
    node: &str,
) -> usize {
    let mut applied_count = 0;
    for taken in Order::take(orders, node) {
        let applied = taken
            .map_err(|problem| format!("an order no node can take: {problem}"))
            .and_then(|order| match order.noun {
                Noun::Subscription => running.pickup().act(&order.target, order.act, &order.who),
                Noun::EventSubscription => Err(format!(
                    "REFUSED: {node} keeps no Event subscription hub; the Event \
                     subscription '{}' is another process's",
                    order.target
                )),
            });
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
