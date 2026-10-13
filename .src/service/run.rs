//! The one way `xmip-service` runs a node, whichever stop it waits for:
//! start it, declare and audit it, publish it, say it is ready, take its
//! orders and publish it again while it waits for the stop, drain it, audit
//! the drain and publish that it stopped.

use std::collections::BTreeMap;
use std::process::ExitCode;
use std::sync::Arc;
use std::sync::mpsc::{Receiver, RecvTimeoutError};
use std::time::Instant;

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

/// Start the node, serve until `stops` names who stopped it, drain it.
/// `ready` is told once the node accepts work, `stopping` once a stop has
/// arrived and before the drain.
pub fn serve(
    program: &str,
    audit: &ProgramAudit,
    arguments: &Arguments,
    stops: &Receiver<StoppedBy>,
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
    let Some((_operate, listening)) = operated(program, audit, configuration, &running, &publisher)
    else {
        let _ = running.stop();
        return Ended::Refused;
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

    let by = loop {
        let applied = orders::take(program, audit, &orders, &location);
        if applied > 0 || publisher.due() {
            publisher.publish(&running);
        }
        match stops.recv_timeout(orders::LOOK) {
            Ok(by) => break by,
            Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => break "its stop closing",
        }
    };
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

/// The node's operate listeners over what `publisher` posts (ADR-0067) —
/// its local endpoint and its network address, each where its
/// configuration's `[operate]` names it — and where they listen; `None`
/// after saying why where one cannot listen, which refuses the node before
/// it accepts work, as every refusal at start does.
fn operated(
    program: &str,
    audit: &ProgramAudit,
    configuration: &str,
    running: &Running,
    publisher: &Publisher,
) -> Option<(Vec<Listener>, Option<String>)> {
    let board: Arc<dyn Published> = publisher.board();
    match running.operate(&board, audit) {
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
