//! The node's publication: what the node `xmip-service` runs says of itself
//! — its health and figures, its topology, its Subscriptions and their
//! standing, and where it takes orders — written where a surface reads it
//! (ADR-0018, amendment 2026-09-30; ADR-0052).
//!
//! The runtime says what the node is (`Running::publication`), observe
//! writes it whole or not at all (`observe::Publication::write`), and this
//! decides only where and when. **Where**: `<data>/snapshot.toml`, beside
//! the node's `orders`, in its data directory (`[service] data`); the
//! service declares it (ADR-0053, `snapshot`), so whoever finds the process
//! finds its publication, and `Start-XmipOperationWeb -Snapshot` opens the
//! operation web over it. **When**: as the node starts to accept work, at
//! the first look after an order was applied, so a pause shows in the next
//! publication and not a round later, and otherwise every [`EVERY`]; and
//! once more after the drain, saying the node stopped
//! (`running::publication::stopped`). It is written on the service's own
//! thread between its looks for a stop: no Receive Location, routing or
//! departure waits for it.
//!
//! A write refused for the instant a reader holds the file — Windows
//! refuses a rename over a file open without delete sharing — is asked
//! again at the next look. One still refused a round later is audited as
//! the failure to `publish` (ADR-0062), once, not at every round, and said
//! once it publishes again.

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use xmip_audit::program_audit::ProgramAudit;
use xmip_observe::Publication;
use xmip_runtime::running::Running;
use xmip_runtime::running::publication::stopped;

use crate::orders::LOOK;
use crate::run;

/// How often the node publishes when nothing an operator did asks sooner.
pub const EVERY: Duration = Duration::from_millis(250);

/// Where the node publishes, beneath its data directory.
pub fn place(running: &Running) -> PathBuf {
    running.data().join("snapshot.toml")
}

/// What publishes the node, and what it published last.
pub struct Publisher<'a> {
    program: &'a str,
    audit: &'a ProgramAudit,
    path: PathBuf,
    orders: String,
    cluster: String,
    node: String,
    written: Option<Instant>,
    last: Option<Publication>,
    failing: Option<Failing>,
}

impl<'a> Publisher<'a> {
    /// A publisher of `running` to `path`, saying a surface leaves its acts
    /// in `orders`.
    pub fn new(
        program: &'a str,
        audit: &'a ProgramAudit,
        running: &Running,
        path: PathBuf,
        orders: &Path,
    ) -> Self {
        Self {
            program,
            audit,
            path,
            orders: orders.display().to_string(),
            cluster: running.cluster().to_string(),
            node: running.node().to_string(),
            written: None,
            last: None,
            failing: None,
        }
    }

    /// Whether [`EVERY`] has passed since the last publication.
    pub fn due(&self) -> bool {
        self.written
            .is_none_or(|written| written.elapsed() >= EVERY)
    }

    /// Publish what the node says of itself now.
    pub fn publish(&mut self, running: &Running) {
        let publication = running
            .publication(self.program)
            .with_orders(self.orders.clone());
        self.write(&publication);
        self.last = Some(publication);
    }

    /// Publish, once the node has drained, that it stopped, saying `said`:
    /// asked again at each look, within a round, where a reader held the
    /// file, since nothing publishes after this.
    pub fn stopped(&mut self, said: &str) {
        let Some(last) = &self.last else {
            return;
        };
        let left = stopped(&self.cluster, &self.node, last, said);
        let began = Instant::now();
        while !self.write(&left) && began.elapsed() < EVERY {
            std::thread::sleep(LOOK);
        }
    }

    /// Write `publication`, and whether it was written. A write refused
    /// once is asked again at the next look — on Windows a reader holding
    /// the file refuses the rename for the instant it reads — and only one
    /// that is still refused a round later is a failure: audited once,
    /// asked again every round, and said when it publishes again.
    fn write(&mut self, publication: &Publication) -> bool {
        match publication.write(&self.path) {
            Ok(()) => {
                self.written = Some(Instant::now());
                if self.failing.take().is_some_and(|failing| failing.audited) {
                    println!(
                        "{}: publishes to {} again",
                        self.program,
                        self.path.display()
                    );
                }
                true
            }
            Err(error) => {
                let since = self
                    .failing
                    .as_ref()
                    .map_or_else(Instant::now, |failing| failing.since);
                let audited = self.failing.as_ref().is_some_and(|failing| failing.audited);
                if audited || since.elapsed() >= EVERY {
                    self.written = Some(Instant::now());
                }
                if !audited && since.elapsed() >= EVERY {
                    let problem = format!(
                        "{}: could not publish to {}: {error}",
                        self.program,
                        self.path.display()
                    );
                    run::fail(self.audit, "publish", &problem);
                }
                self.failing = Some(Failing {
                    since,
                    audited: audited || since.elapsed() >= EVERY,
                });
                false
            }
        }
    }
}

/// Since when the publication has been refused, and whether that was
/// audited.
struct Failing {
    since: Instant,
    audited: bool,
}
