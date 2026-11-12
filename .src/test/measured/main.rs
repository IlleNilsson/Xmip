//! The root's timing program (`doc/governance/rust-style.md` section 5c):
//! `xmip-service` started as `xmip-service` starts it, and Xmip Storage
//! reached as a node reaches it, held to how long Xmip takes: the
//! millisecond rule (`CONTRIBUTING.md`, *Rust is here for one reason*). A
//! plain `cargo test` leaves it out; the landing runs it after every other
//! test of the root, alone, one test at a time (`cargo test --test measured
//! -- --test-threads=1`), so what is measured is Xmip's work and not its
//! neighbors':
//!
//! - `carried.rs`: the getting-started node — roles executing and storage —
//!   carries a file dropped in its drop directory, accepted by the
//!   circumstance, to a file of the same name in its send directory, whole,
//!   audited, with Xmip's own work measured against the millisecond rule;
//!   and, where the build links `content` and `edi`, the same with an
//!   EDIFACT order routed by its message type, promoted from the content
//!   (ADR-0046, amendment 2026-11-11).
//! - `told.rs`: an order is acted on the moment it is left, within about a
//!   millisecond beyond what it carries, and a service nothing tells uses
//!   next to no processor.
//! - `publication.rs`: the node publishes its snapshot where it declares,
//!   read by observe's one reader; a pause left where the snapshot says the
//!   node takes orders shows paused in the next one, at once; and the stop
//!   leaves it saying so.
//! - `wire.rs`: a read and a write over the wire to the primary of two
//!   Storage nodes, its standby copying every write behind it, cost less
//!   than a millisecond beyond the same calls in process.
//! - `woken.rs`: a Journey one node publishes into a queue, or hands on
//!   into one, is told to another node waiting on that queue over the wire
//!   within a millisecond of the write's answer (open problem 46).
//!
//! What it starts and opens is the other programs' own, shared, not
//! copied: the service's `started.rs`, and the Storage tests' `node.rs`
//! and `authority.rs`.

use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::mpsc::Receiver;
use std::time::{Duration, Instant};

use xmip_net::fixture::unheld;
use xmip_observe::{Act, Noun, Order};

#[path = "../service/started.rs"]
mod started;
use started::*;

#[allow(dead_code)]
#[path = "../storage/authority.rs"]
mod authority;
#[allow(dead_code)]
#[path = "../storage/node.rs"]
mod node;

mod carried;
mod publication;
mod told;
mod wire;
mod woken;
