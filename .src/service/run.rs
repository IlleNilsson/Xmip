//! The one way `xmip-service` runs a node, whichever stop it waits for:
//! start it, declare and audit it, publish it, say it is ready, publish it
//! again as acts are taken and rounds are due while it waits for the stop,
//! drain it, audit the drain and publish that it stopped.
//!
//! The start is the runtime's order (`running::activation::started`;
//! ADR-0031, amendment 2026-11-12): the node's candidate tried first, the
//! program's own steps part of the attempt (`opened`), and, where any step
//! refuses it, the same attempt over the node's active configuration. Only
//! when nothing runs is the start refused.
//!
//! While it serves, the service waits to be told ([`Told`]), using no
//! processor: by a stop — the Service Control Manager's, a signal from
//! systemd or launchd, the console's Ctrl+C — and by the node's act watch
//! that it took an act asked of it through Xmip Storage
//! (`xmip_runtime::act_watch`). Each wakes it the moment it arrives; only the
//! publication's round, [`publication::EVERY`], wakes it otherwise.

use std::process::ExitCode;
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::time::{Duration, Instant};

use xmip_audit::program_audit::ProgramAudit;
use xmip_core::ExecutionPhase;
use xmip_node::Declaration;
use xmip_runtime::declared::declare;
use xmip_runtime::outcome::Outcomes;
use xmip_runtime::plane::deadline;
use xmip_runtime::registration::REFUSED;
use xmip_runtime::running::Running;
use xmip_runtime::running::activation;

use crate::arguments::Arguments;
use crate::audit::{fail, record};
use crate::opened::{Opened, configured, opened};
use crate::publication::{self, Publisher};
use crate::{authority, built};

/// Who stopped the node, as the stop record says it.
pub type StoppedBy = &'static str;

/// What the service is told while it serves.
#[derive(Debug, PartialEq, Eq)]
pub enum Told {
    /// Stop, by whom.
    Stop(StoppedBy),
    /// Its act watch took an act asked of it.
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
    let started = activation::started(
        configuration,
        || built::linked(audit),
        |running| opened((program, audit), configuration, running, tell),
    );
    let (running, held) = match started {
        Ok(started) => started,
        Err(refusal) => {
            fail(
                audit,
                "start",
                &format!("{program}: {configuration} {refusal}"),
            );
            return Ended::Refused;
        }
    };
    let Opened {
        mut publisher,
        operate: _operate,
        listening,
        authority: serving,
    } = held;
    let location = running.location();
    // Every record from here carries the location it declares, so a reader
    // knows whose it is (ADR-0062, amendment 2026-09-29).
    audit.locate(&location);
    configured(program, audit, &running);
    if let Some(serving) = &serving {
        authority::said(program, audit, serving);
    }
    let snapshot = publication::place(&running).display().to_string();

    // What this process says of itself while it runs (ADR-0053); the file
    // goes when `declared` does, after the drain.
    let declared = Declaration::new(program, location.as_str(), arguments.purpose)
        .and_then(|declaration| declaration.with("configuration", configuration))
        .and_then(|declaration| declaration.with("snapshot", snapshot.as_str()))
        .and_then(|declaration| match listening.as_deref() {
            Some(operate) => declaration.with("operate", operate),
            None => Ok(declaration),
        })
        .and_then(|declaration| {
            let within = running.local_timeout().as_millis().to_string();
            declaration.with(deadline::DECLARED, within)
        })
        .and_then(|declaration| declare(&declaration).map_err(|error| error.to_string()));
    if let Err(problem) = &declared {
        fail(
            audit,
            "declare",
            &format!("{program}: could not declare itself: {problem}"),
        );
    }
    let said = running.storage().said();
    record(
        audit,
        "start",
        ExecutionPhase::Begin,
        &[
            ("node", location.as_str()),
            ("configuration", configuration),
            ("purpose", arguments.purpose.word()),
            ("storage", said.as_str()),
            ("snapshot", snapshot.as_str()),
            ("operate", listening.as_deref().unwrap_or("")),
        ],
    );
    say_where(
        &format!("{program}: {location}"),
        &running,
        &snapshot,
        listening.as_deref(),
    );
    publisher.publish(&running);
    println!("{program}: {location} accepts work");
    ready();

    let by = served(program, audit, &running, &mut publisher, told);
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

/// Serve `running` until `told` says who stopped it: publish at once after
/// an act its act watch took, and otherwise when the round is due.
fn served(
    program: &str,
    audit: &ProgramAudit,
    running: &Running,
    publisher: &mut Publisher,
    told: &Receiver<Told>,
) -> StoppedBy {
    // The authority's list, kept current where the node keeps it (ADR-0034).
    let mut list = running.revocation_list();
    let mut acted = false;
    loop {
        if let Err(problem) = list.keep() {
            fail(audit, "revocation-list", &format!("{program}: {problem}"));
        }
        if acted || publisher.due() {
            publisher.publish(running);
        }
        match hear(told, publisher.next()) {
            Ok(now) => acted = now,
            Err(by) => return by,
        }
    }
}

/// What `told` says within `within`, every message waiting heard at once,
/// so a burst of changes is one look: whether an act was taken — or who
/// stopped the node.
fn hear(told: &Receiver<Told>, within: Duration) -> Result<bool, StoppedBy> {
    let first = match told.recv_timeout(within) {
        Ok(first) => first,
        Err(RecvTimeoutError::Timeout) => return Ok(false),
        Err(RecvTimeoutError::Disconnected) => return Err("its stop closing"),
    };
    let mut acted = false;
    for heard in std::iter::once(first).chain(told.try_iter()) {
        match heard {
            Told::Stop(by) => return Err(by),
            Told::Acted => acted = true,
        }
    }
    Ok(acted)
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
    // Xmip's own share of a sent Message's time, the fastest of five, where
    // the node measured one (`Outcomes::own_share`): what the millisecond
    // rule holds; and the disk's time beside it (`Outcomes::disk_sync`),
    // which it never holds.
    let measured = [
        ("own_share_ns", outcomes.own_share),
        ("disk_sync_ns", outcomes.disk_sync),
    ]
    .map(|(name, taken)| (name, taken.map(|taken| taken.as_nanos().to_string())));
    for (name, taken) in &measured {
        if let Some(taken) = taken {
            properties.push((*name, taken.as_str()));
        }
    }
    // Where its stop left its membership row saying it runs, why, in the
    // runtime's words (`Outcomes::membership`).
    if let Some(why) = outcomes.membership {
        properties.push(("membership", why));
    }
    record(audit, "stop", ExecutionPhase::Finished, &properties);
    let share = outcomes
        .own_share
        .map(|own| format!("; Xmip's own share per Message {own:?}"))
        .unwrap_or_default();
    let disk = outcomes
        .disk_sync
        .map(|disk| format!(", the disk's sync beside it {disk:?}"))
        .unwrap_or_default();
    let membership = outcomes
        .membership
        .map(|why| format!("; {why}"))
        .unwrap_or_default();
    format!(
        "stopped by {by}, drained in {drained} ms: {}{share}{disk}{membership}",
        counts
            .iter()
            .map(|(name, count)| format!("{name} {count}"))
            .collect::<Vec<_>>()
            .join(", ")
    )
}

/// Say on the console where the node `who` names keeps what it keeps.
fn say_where(who: &str, running: &Running, snapshot: &str, operate: Option<&str>) {
    println!(
        "{who} reaches Xmip Storage through {}",
        running.storage().said()
    );
    println!("{who} publishes its snapshot at {snapshot}");
    if let Some(operate) = operate {
        println!("{who} is operated at {operate}");
    }
}
