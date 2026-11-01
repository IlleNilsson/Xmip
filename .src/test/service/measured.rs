//! The root's timing program (`doc/governance/rust-style.md` section 5c):
//! `xmip-service` started as `xmip-service` starts it (`started.rs`), and
//! held to how long Xmip takes: the millisecond rule (`CONTRIBUTING.md`,
//! *Rust is here for one reason*). A plain `cargo test` leaves it out; the
//! landing runs it after every other test of the root, alone, one test at a
//! time (`cargo test --test measured -- --test-threads=1`), so what is
//! measured is Xmip's work and not its neighbors':
//!
//! - `carried.rs`: the getting-started node — roles executing and storage —
//!   carries a file dropped in its drop directory, accepted by the
//!   circumstance, to a file of the same name in its send directory, whole,
//!   audited, with Xmip's own work measured against the millisecond rule.
//! - `told.rs`: an order is acted on the moment it is left, within about a
//!   millisecond beyond what it carries, and a service nothing tells uses
//!   next to no processor.

use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::mpsc::Receiver;
use std::time::{Duration, Instant};

use xmip_net::fixture::unheld;
use xmip_observe::{Act, Noun, Order};

mod started;
use started::*;

mod carried;
mod told;
