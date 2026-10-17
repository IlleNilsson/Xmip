//! The one way `xmip-service` runs a node, whichever stop it waits for:
//! start it, declare and audit it, publish it, say it is ready, take its
//! orders and publish it again while it waits for the stop, drain it, audit
//! the drain and publish that it stopped.
//!
//! While it serves, the service waits to be told ([`Told`]), using no
//! processor: by a stop — the Service Control Manager's, a signal from
//! systemd or launchd, the console's Ctrl+C — by the operating system that
//! an order was left where it takes them, and by its operate listener that
//! an act was taken there. Each wakes it the moment it arrives; only the
//! publication's round, [`publication::EVERY`], wakes it otherwise.

use std::collections::BTreeMap;
use std::path::Path;
use std::process::ExitCode;
use std::sync::Arc;
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::time::{Duration, Instant};

use xmip_audit::program_audit::ProgramAudit;
use xmip_core::{ExecutionPhase, Severity};
use xmip_node::Declaration;
use xmip_runtime::outcome::Outcomes;
use xmip_runtime::plane::{Listener, Published, deadline};
use xmip_runtime::registration::REFUSED;
use xmip_runtime::running::Running;

use crate::arguments::Arguments;
use crate::publication::{self, Publisher};
use crate::{built, orders};

/// Who stopped the node, as the stop record says it.
pub type StoppedBy = &'static str;

/// What the service is told while it serves.
#[derive(Debug, PartialEq, Eq)]
pub enum Told {
    /// Stop, by whom.
    Stop(StoppedBy),
    /// The place it takes orders changed: one may have been left.
    Orders,
    /// An act was taken over its operate listener.
    Acted,
}

/// How a run ended.
#[derive(Debug)]
pub enum Ended {
    /// Stopped and drained.
    Stopped,
    /// Refused before anything served.
    Refused,
}

impl Ended {
    /// The process's exit code: 0 for a drain, [`REFUSED`] for a refusal.
    pub fn code(&self) -> ExitCode {
        match self {
            Self::Stopped => ExitCode::SUCCESS,
            Self::Refused => ExitCode::from(REFUSED),
        }
    }
}

/// Start the node, serve until `told` says who stopped it, drain it. What
/// tells the service while it serves is given `tell`, the sender of
/// `told`. `ready` is told once the node accepts work, `stopping` once a
/// stop has arrived and before the drain.
pub fn serve(
    program: &str,
    audit: &ProgramAudit,
    arguments: &Arguments,
    (tell, told): (&Sender<Told>, &Receiver<Told>),
    ready: impl FnOnce(),
    stopping: impl FnOnce(),
) -> Ended {
    let configuration = arguments.configuration.as_str();
    let running = match Running::start(configuration, built::linked(audit)) {
        Ok(running) => running,
        Err(refusal) => {
            fail(
                audit,
                "start",
                &format!("{program}: {configuration} {refusal}"),
            );
            return Ended::Refused;
        }
    };
    let location = running.location();
    let orders = orders::place(&running);
    let place = orders.display().to_string();
    let publication_path = publication::place(&running);
    let snapshot = publication_path.display().to_string();
    let mut publisher = Publisher::new(program, audit, &running, publication_path, &orders);
    let board = publisher.board(tell);
    let Some((_operate, listening)) = operated(program, audit, configuration, &running, &board)
    else {
        let _ = running.stop();
        return Ended::Refused;
    };
    let watch = match orders::watch(&orders, &location, tell) {
        Ok(watch) => watch,
        Err(problem) => {
            fail(audit, "orders", &format!("{program}: {problem}"));
            let _ = running.stop();
            return Ended::Refused;
        }
    };
    // Every record from here carries the location it declares, so a reader
    // knows whose it is (ADR-0062, amendment 2026-09-29).
    audit.locate(&location);

    // What this process says of itself while it runs (ADR-0053); the file
    // goes when `declared` does, after the drain.
    let declared = Declaration::new(program, location.as_str(), arguments.purpose)
        .with("configuration", configuration)
        .and_then(|declaration| declaration.with("orders", place.as_str()))
        .and_then(|declaration| declaration.with("snapshot", snapshot.as_str()))
        .and_then(|declaration| match listening.as_deref() {
            Some(operate) => declaration.with("operate", operate),
            None => Ok(declaration),
        })
        .and_then(|declaration| {
            let within = running.local_timeout().as_millis().to_string();
            declaration.with(deadline::DECLARED, within)
        })
        .and_then(|declaration| declaration.declare().map_err(|error| error.to_string()));
    if let Err(problem) = &declared {
        fail(
            audit,
            "declare",
            &format!("{program}: could not declare itself: {problem}"),
        );
    }
    record(
        audit,
        "start",
        ExecutionPhase::Begin,
        &[
            ("node", location.as_str()),
            ("configuration", configuration),
            ("purpose", arguments.purpose.word()),
            ("storage", running.storage().said()),
            ("orders", place.as_str()),
            ("snapshot", snapshot.as_str()),
            ("operate", listening.as_deref().unwrap_or("")),
        ],
    );
    say_where(
        &format!("{program}: {location}"),
        &running,
        &place,
        &snapshot,
        listening.as_deref(),
    );
    publisher.publish(&running);
    println!("{program}: {location} accepts work");
    ready();

    let by = served(program, audit, &running, &orders, &mut publisher, told);
    drop(watch);
    stopping();
    let draining = Instant::now();
    let outcomes = running.stop();
    let drained = draining.elapsed().as_millis().to_string();

    let said = drained_record(audit, &location, by, outcomes, &drained);
    publisher.stopped(&said);
    println!("{program}: {location} {said}");
    drop(declared);
    Ended::Stopped
}

/// Serve `running` until `told` says who stopped it: take the orders left
/// in `orders` when told one may have been, and publish at once after an
/// order or an act, and otherwise when the round is due.
fn served(
    program: &str,
    audit: &ProgramAudit,
    running: &Running,
    orders: &Path,
    publisher: &mut Publisher,
    told: &Receiver<Told>,
) -> StoppedBy {
    let location = running.location();
    // Orders left before the watch began are taken at once.
    let (mut taking, mut acted) = (true, false);
    loop {
        let applied = if taking {
            orders::take(program, audit, orders, &location)
        } else {
            0
        };
        if applied > 0 || acted || publisher.due() {
            publisher.publish(running);
        }
        match hear(told, publisher.next()) {
            Ok(now) => (taking, acted) = now,
            Err(by) => return by,
        }
    }
}

/// What `told` says within `within`, every message waiting heard at once,
/// so a burst of changes is one look: whether orders may have been left
/// and whether an act was taken — or who stopped the node.
fn hear(told: &Receiver<Told>, within: Duration) -> Result<(bool, bool), StoppedBy> {
    let first = match told.recv_timeout(within) {
        Ok(first) => first,
        Err(RecvTimeoutError::Timeout) => return Ok((false, false)),
        Err(RecvTimeoutError::Disconnected) => return Err("its stop closing"),
    };
    let (mut orders, mut acted) = (false, false);
    for heard in std::iter::once(first).chain(told.try_iter()) {
        match heard {
            Told::Stop(by) => return Err(by),
            Told::Orders => orders = true,
            Told::Acted => acted = true,
        }
    }
    Ok((orders, acted))
}

/// Record the stop of the node at `location` by `by`, drained in `drained`
/// milliseconds with `outcomes`, and say it in one sentence.
fn drained_record(
    audit: &ProgramAudit,
    location: &str,
    by: StoppedBy,
    outcomes: Outcomes,
    drained: &str,
) -> String {
    let counts = [
        ("received", outcomes.received),
        ("routed", outcomes.routed),
        ("unroutable", outcomes.unroutable),
        ("refused", outcomes.refused),
        ("failed", outcomes.failed),
        ("sent", outcomes.sent),
        ("not_sent", outcomes.not_sent),
    ]
    .map(|(name, count)| (name, count.to_string()));
    let mut properties = vec![("node", location), ("by", by), ("drained_ms", drained)];
    properties.extend(counts.iter().map(|(name, count)| (*name, count.as_str())));
    record(audit, "stop", ExecutionPhase::Finished, &properties);
    let said = format!(
        "stopped by {by}, drained in {drained} ms: {}",
        counts
            .iter()
            .map(|(name, count)| format!("{name} {count}"))
            .collect::<Vec<_>>()
            .join(", ")
    );
    said
}

/// The node's operate listeners over what `board` holds (ADR-0067) —
/// its local endpoint and its network address, each where its
/// configuration's `[operate]` names it — and where they listen; `None`
/// after saying why where one cannot listen, which refuses the node before
/// it accepts work, as every refusal at start does.
fn operated(
    program: &str,
    audit: &ProgramAudit,
    configuration: &str,
    running: &Running,
    board: &Arc<dyn Published>,
) -> Option<(Vec<Listener>, Option<String>)> {
    match running.operate(board, audit) {
        Ok(operate) => {
            let listening = (!operate.is_empty()).then(|| {
                operate
                    .iter()
                    .map(Listener::address)
                    .collect::<Vec<_>>()
                    .join(" and ")
            });
            Some((operate, listening))
        }
        Err(refusal) => {
            fail(
                audit,
                "operate",
                &format!("{program}: {configuration} {refusal}"),
            );
            None
        }
    }
}

/// Say on the console where the node `who` names keeps what it keeps.
fn say_where(who: &str, running: &Running, orders: &str, snapshot: &str, operate: Option<&str>) {
    println!(
        "{who} reaches Xmip Storage through {}",
        running.storage().said()
    );
    println!("{who} takes orders at {orders}");
    println!("{who} publishes its snapshot at {snapshot}");
    if let Some(operate) = operate {
        println!("{who} is operated at {operate}");
    }
}

/// Say `problem` on stderr and record it as the failure of `action`: a
/// failure is never only on a screen (ADR-0062 clause 4).
pub fn fail(audit: &ProgramAudit, action: &str, problem: &str) {
    eprintln!("{problem}");
    kept(audit.failed(action, problem));
}

pub fn record(
    audit: &ProgramAudit,
    action: &str,
    phase: ExecutionPhase,
    properties: &[(&str, &str)],
) {
    let properties: BTreeMap<String, String> = properties
        .iter()
        .map(|(key, value)| ((*key).to_string(), (*value).to_string()))
        .collect();
    kept(audit.record(action, phase, Severity::Information, None, properties));
}

/// A record neither the sink nor the operating system's log kept is said on
/// stderr, the last place left.
fn kept<T>(outcome: Result<T, xmip_audit::AuditError>) {
    if let Err(error) = outcome {
        eprintln!("audit: {error}");
    }
}
