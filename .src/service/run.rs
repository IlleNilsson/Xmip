//! The one way `xmip-service` runs a node, whichever stop it waits for:
//! start it, declare and audit it, say it is ready, wait for the stop, drain
//! it, audit the drain.

use std::collections::BTreeMap;
use std::process::ExitCode;
use std::sync::mpsc::Receiver;
use std::time::Instant;

use xmip_audit::program_audit::ProgramAudit;
use xmip_core::{ExecutionPhase, Severity};
use xmip_node::Declaration;
use xmip_runtime::registration::REFUSED;
use xmip_runtime::running::Running;

use crate::arguments::Arguments;
use crate::built;

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
    let running = match Running::start(configuration, built::linked()) {
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
    let location = format!("xmip:///{}/node/{}", running.cluster(), running.node());

    // What this process says of itself while it runs (ADR-0053); the file
    // goes when `declared` does, after the drain.
    let declared = Declaration::new(program, location.as_str(), arguments.purpose)
        .with("configuration", configuration)
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
        ],
    );
    println!("{program}: {location} accepts work");
    ready();

    let by = stops.recv().unwrap_or("its stop closing");
    stopping();
    let draining = Instant::now();
    let outcomes = running.stop();
    let drained = draining.elapsed().as_millis().to_string();

    let counts = [
        ("received", outcomes.received),
        ("routed", outcomes.routed),
        ("unroutable", outcomes.unroutable),
        ("refused", outcomes.refused),
        ("sent", outcomes.sent),
        ("not_sent", outcomes.not_sent),
    ]
    .map(|(name, count)| (name, count.to_string()));
    let mut properties = vec![
        ("node", location.as_str()),
        ("by", by),
        ("drained_ms", drained.as_str()),
    ];
    properties.extend(counts.iter().map(|(name, count)| (*name, count.as_str())));
    record(audit, "stop", ExecutionPhase::Finished, &properties);
    println!(
        "{program}: {location} stopped by {by}, drained in {drained} ms: {}",
        counts
            .iter()
            .map(|(name, count)| format!("{name} {count}"))
            .collect::<Vec<_>>()
            .join(", ")
    );
    drop(declared);
    Ended::Stopped
}

/// Say `problem` on stderr and record it as the failure of `action`: a
/// failure is never only on a screen (ADR-0062 clause 4).
pub fn fail(audit: &ProgramAudit, action: &str, problem: &str) {
    eprintln!("{problem}");
    kept(audit.failed(action, problem));
}

fn record(audit: &ProgramAudit, action: &str, phase: ExecutionPhase, properties: &[(&str, &str)]) {
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
