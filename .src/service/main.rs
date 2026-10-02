//! `xmip-service`: the Xmip Service, the one program the operating system
//! starts (ADR-0018, amendment 2026-09-26).
//!
//! ```text
//! xmip-service --configuration <path> [--console] [--purpose test|runtime]
//! xmip-service --configuration <path> --definition
//! ```
//!
//! It starts the node configured at `<path>` with the technologies this build
//! linked (`running::Running::start`), serves until it is stopped, and then
//! drains it (`Running::stop`, ADR-0018 clause 12) and exits 0. Every stop is
//! the same drain, however it arrives:
//!
//! - **Windows, as a service**: the service control manager's Stop or
//!   Shutdown (`control_manager.rs`).
//! - **Linux, as a systemd unit, and macOS, as a launchd daemon**: SIGTERM,
//!   which is how both stop a service; systemd is told the node is ready once
//!   it accepts work (`readiness.rs`).
//! - **In a console, `--console`, on every platform**: Ctrl+C (and on Linux
//!   and macOS SIGTERM and SIGHUP too) (`console.rs`).
//!
//! A node its configuration or this build cannot start is refused before
//! anything serves, in words, with exit code 2, which no service manager
//! restarts (`registration::REFUSED`). Nothing here restarts anything: the
//! service manager owns restarts, and nothing in Xmip starts itself.
//!
//! `--definition` prints what this platform's service manager is told about
//! the node's service — a systemd unit, a launchd property list, or the
//! `sc.exe create` arguments one per line — from `registration.rs`, the one
//! place it is written, so an installer registers what the runtime generates.
//!
//! The node keeps its runtime store where its configuration's `[store]`
//! says, over `RocksDB`, the one engine, sealed under the platform's key
//! store (ADR-0018, amendments 2026-09-30 and 2026-10-01); a build without
//! `RocksDB`, a store naming a key store this build left out, or one that
//! does not open, is refused as any node that cannot start is. While it serves it takes the orders an operator leaves
//! for it — a pause or a resume of a Subscription — from `<data>/orders`
//! (`orders.rs`), and publishes what the node says of itself — its health,
//! figures, topology and Subscriptions — to `<data>/snapshot.toml`, every
//! quarter of a second and at once after an order, where the operation
//! surfaces read it (`publication.rs`; ADR-0018, amendment 2026-09-30).
//!
//! It declares itself (ADR-0053) — its configuration, its orders and its
//! snapshot among what it says — and audits its start, its stop, every
//! order and every failure (ADR-0062).

mod arguments;
mod built;
mod console;
#[cfg(windows)]
mod control_manager;
mod definition;
mod orders;
mod publication;
mod readiness;
mod run;

use std::process::ExitCode;

use xmip_audit::program_audit::ProgramAudit;

use crate::arguments::{Arguments, Mode, USAGE};

/// The name ADR-0053 gives this program, where its image says nothing else.
const PROGRAM: &str = "xmip-service";

fn main() -> ExitCode {
    // The declaration and the audit say the name the operating system lists
    // this process under, read from its own image (ADR-0053 clause 6).
    let program = std::env::current_exe()
        .ok()
        .as_deref()
        .and_then(std::path::Path::file_stem)
        .and_then(|stem| stem.to_str())
        .map_or_else(|| PROGRAM.to_string(), ToString::to_string);
    let audit = ProgramAudit::new(&program, None);
    audit.watch_panics();

    let arguments = match Arguments::parse(std::env::args().skip(1)) {
        Ok(arguments) => arguments,
        Err(problem) => {
            run::fail(&audit, "start", &format!("{program}: {problem}"));
            eprintln!("{USAGE}");
            return ExitCode::from(xmip_runtime::registration::REFUSED);
        }
    };

    match arguments.mode {
        Mode::Definition => definition::print(&audit, &arguments),
        Mode::Console => console::run(&program, &audit, &arguments),
        #[cfg(windows)]
        Mode::Service => control_manager::run(program, audit, arguments),
        // systemd and launchd stop a service with SIGTERM, which the
        // console's stop already takes.
        #[cfg(not(windows))]
        Mode::Service => console::run(&program, &audit, &arguments),
    }
}
