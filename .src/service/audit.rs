//! What `xmip-service` audits of itself, whichever mode it runs in
//! (ADR-0062): a failure, said on stderr too and recorded as the failure of
//! what it was doing, and an action's record with what it says.

use std::collections::BTreeMap;

use xmip_audit::program_audit::ProgramAudit;
use xmip_core::{ExecutionPhase, Severity};

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
