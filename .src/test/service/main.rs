//! `xmip-service` started in a console over loopback, as an operating
//! system or a terminal starts it, and held to what it does (ADR-0018,
//! amendments 2026-09-28 and 2026-09-30). What every test here starts it
//! with is `started.rs`, shared with the timing program `measured`; each test is
//! in the file named for what it proves:
//!
//! - `stop.rs`: a stop drains the node and the process exits 0, within a
//!   bound, having declared and audited itself; a node it cannot start, or
//!   a Storage node it cannot open, is refused with exit 2; a Subscription paused
//!   through an order is paused still after a restart.
//! - `operate.rs`: a node configured with `[operate]` is reached on its
//!   operate listener as a surface on another machine reaches it, its
//!   publication read and an act taken as the certificate's subject.
//! - `accepted.rs`: a Receive Location terminating TLS with the node's
//!   `[provision.receive]` certificate accepts a Stream from the Party its
//!   `accept.party` names, through the build's own identity technologies,
//!   and refuses and audits one whose certificate names another.
//! - `failover.rs`: a receiving and a sending node reach the test cluster's
//!   two Storage nodes over Xmip's mutual TLS, keeping none themselves;
//!   the primary Storage node is stopped while files are dropped, its
//!   standby is not promoted and nothing more is taken in until the
//!   primary is started again, and then every file dropped arrives once,
//!   whole.
//! - `authority.rs`: a node whose `[provision.node]` serves the cluster's
//!   authority answers ACME for the premises and publishes its revocation
//!   list, `--listening` names both ports, and a client obtains, is told
//!   when to renew and revokes into the list while the node runs.
//! - `routed.rs`: where the build links the `content` route technology and
//!   the `edi` path language, an EDIFACT document dropped in goes to the
//!   Send Port its message type and recipient name, whole, and one no
//!   Subscription takes goes nowhere.
//!
//! A test that measures how long Xmip takes is not here: it is in the
//! root's timing program, `measured` (`.src/test/measured`), which the
//! landing runs after this one, alone, one test at a time, so what it
//! measures is Xmip's work and not these tests'
//! (`doc/governance/rust-style.md` section 5c). The node's publication, a
//! pause left where it takes orders shown paused at once, is there too.
//!
//! Every Message is received and settled. Each reaches the first gate with
//! what its transport observed, and the build's `ip` identifier claims its
//! peer on the transport layer, passed. Where the Receive Location's
//! configuration declares no `accept`, it accepts nothing: every Message is
//! refused at authentication, by name, counted, and audited with the claim
//! it carried.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use xmip_net::fixture::unheld;
use xmip_observe::Act;

mod started;
use started::*;

mod accepted;
mod authority;
mod failover;
mod operate;
#[cfg(all(feature = "route-content", feature = "path-edi"))]
mod routed;
mod stop;
