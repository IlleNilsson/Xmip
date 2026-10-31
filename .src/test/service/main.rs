//! `xmip-service` started in a console over loopback, as an operating
//! system or a terminal starts it, and held to what it does (ADR-0018,
//! amendments 2026-09-28 and 2026-09-30). What every test here starts it
//! with is `started.rs`, shared with `xmip-service-measured`; each test is
//! in the file named for what it proves:
//!
//! - `stop.rs`: a stop drains the node and the process exits 0, within a
//!   bound, having declared and audited itself; a node it cannot start, or
//!   a Storage node it cannot open, is refused with exit 2; a Subscription paused
//!   through an order is paused still after a restart.
//! - `operate.rs`: a node configured with `[operate]` is reached on its
//!   operate listener as a surface on another machine reaches it, its
//!   publication read and an act taken as the certificate's subject.
//! - `publication.rs`: the node publishes its snapshot where it declares,
//!   read by observe's one reader; a pause left where the snapshot says the
//!   node takes orders shows paused in the next one; and the stop leaves it
//!   saying so.
//! - `accepted.rs`: a Receive Location terminating TLS with the node's
//!   `[provision.receive]` certificate accepts a Stream from the Party its
//!   `accept.party` names, through the build's own identity technologies,
//!   and refuses and audits one whose certificate names another.
//! - `failover.rs`: a receiving and a sending node reach the test cluster's
//!   two Storage nodes over Xmip's mutual TLS, keeping none themselves;
//!   the primary Storage node is stopped while files are dropped, its
//!   standby is promoted, and every file dropped arrives once, whole.
//! - `authority.rs`: a node whose `[provision.node]` serves the cluster's
//!   authority answers ACME for the premises and publishes its revocation
//!   list, `--listening` names both ports, and a client obtains, is told
//!   when to renew and revokes into the list while the node runs.
//!
//! A test that measures how long Xmip takes is not here: it is in
//! `xmip-service-measured` (`measured.rs`), a program of its own that cargo
//! runs after this one, so what it measures is Xmip's work and not these
//! tests'.
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
use xmip_observe::{Act, Noun, Order};
use xmip_transport::Transport;
use xmip_transport_tcp::TcpTransport;

mod started;
use started::*;

const MESSAGES: u64 = 50;

/// Send one Message, asking again while the Receive Location has not yet
/// bound — it binds on its first receive. Bounded, and never a sleep.
fn deliver(address: &str, payload: &[u8]) {
    let deadline = Instant::now() + Duration::from_secs(5);
    loop {
        match TcpTransport::loopback().send(address, payload) {
            Ok(()) => return,
            Err(refused) if refused.retryable && Instant::now() < deadline => {
                std::thread::yield_now();
            }
            Err(failed) => panic!("the node took nothing at {address}: {failed:?}"),
        }
    }
}

fn declarations(directory: &Path) -> Vec<String> {
    std::fs::read_dir(directory.join("process"))
        .map(|entries| {
            entries
                .flatten()
                .filter_map(|entry| std::fs::read_to_string(entry.path()).ok())
                .collect()
        })
        .unwrap_or_default()
}

mod accepted;
mod authority;
mod failover;
mod operate;
mod publication;
mod stop;
