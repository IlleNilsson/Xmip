//! `xmip-service` started as `xmip-service` starts it (`started.rs`), and
//! held to how long Xmip takes: the millisecond rule (`CONTRIBUTING.md`,
//! *Rust is here for one reason*). A program of its own, apart from
//! `xmip-service`'s tests, which cargo runs before it and never beside it,
//! so what is measured is Xmip's work and not its neighbors':
//!
//! - `carried.rs`: the getting-started node — roles executing and storage —
//!   carries a file dropped in its drop directory, accepted by the
//!   circumstance, to a file of the same name in its send directory, whole,
//!   audited, with Xmip's own work measured against the millisecond rule.
//! - `told.rs`: an order is acted on the moment it is left, within about a
//!   millisecond beyond what it carries, and a service nothing tells uses
//!   next to no processor.
//!
//! Each takes the machine whole ([`alone`]): no other test of this program
//! runs beside it.

use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::mpsc::Receiver;
use std::sync::{Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};

use xmip_net::fixture::unheld;
use xmip_observe::{Act, Noun, Order};

mod started;
use started::*;

/// The machine the tests here run on, taken whole by each.
static MACHINE: Mutex<()> = Mutex::new(());

/// The machine, no other test of this program running beside it, for as
/// long as the guard is held.
fn alone() -> MutexGuard<'static, ()> {
    MACHINE.lock().unwrap_or_else(PoisonError::into_inner)
}

mod carried;
mod told;
