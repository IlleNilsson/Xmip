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
//! once after an order was applied or an act taken over the operate
//! listener — the listener tells the service (`Published::acted`) — so a
//! pause shows in the next publication and not a round later, and
//! otherwise every [`EVERY`]; and once more after the drain, saying the
//! node stopped (`running::publication::stopped`). It is written on the
//! service's own thread while it waits to be told: no Receive Location,
//! routing or departure waits for it. Each is posted, as written, to the
//! board the node's operate listener answers from (`[operate]`; ADR-0014,
//! amendment 2026-10-12), so a surface following the node from another
//! machine is told at once.
//!
//! A write refused for the instant a reader holds the file — Windows
//! refuses a rename over a file open without delete sharing — is asked
//! again [`AGAIN`] later. One still refused a round later is audited as
//! the failure to `publish` (ADR-0062), once, not at every round, and said
//! once it publishes again.

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::mpsc::Sender;
use std::time::{Duration, Instant};

use xmip_audit::program_audit::ProgramAudit;
use xmip_observe::Publication;
use xmip_runtime::plane::{Board, Published};
use xmip_runtime::running::Running;
use xmip_runtime::running::publication::stopped;

use crate::run::{self, Told};

/// How often the node publishes when nothing an operator did asks sooner.
pub const EVERY: Duration = Duration::from_millis(250);

/// How soon a write a reader refused is asked again: a reader holds the
/// file for the instant it reads it.
pub const AGAIN: Duration = Duration::from_millis(1);

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
    board: Arc<Board>,
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
            board: Arc::default(),
        }
    }

    /// The board every publication is posted to, which the node's operate
    /// listener answers from, telling `tell` of every act it takes.
    pub fn board(&self, tell: &Sender<Told>) -> Arc<dyn Published> {
        Arc::new(Telling {
            board: Arc::clone(&self.board),
            tell: tell.clone(),
        })
    }

    /// Whether [`EVERY`] has passed since the last publication.
    pub fn due(&self) -> bool {
        self.written
            .is_none_or(|written| written.elapsed() >= EVERY)
    }

    /// How long until a publication is due: what is left of [`EVERY`]
    /// since the last, or [`AGAIN`] while a reader refuses the write.
    pub fn next(&self) -> Duration {
        if self
            .failing
            .as_ref()
            .is_some_and(|failing| !failing.audited)
        {
            return AGAIN;
        }
        self.written.map_or(Duration::ZERO, |written| {
            EVERY.saturating_sub(written.elapsed())
        })
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
    /// asked again every [`AGAIN`], within a round, where a reader held the
    /// file, since nothing publishes after this.
    pub fn stopped(&mut self, said: &str) {
        let Some(last) = &self.last else {
            return;
        };
        let left = stopped(&self.cluster, &self.node, last, said);
        let began = Instant::now();
        while !self.write(&left) && began.elapsed() < EVERY {
            std::thread::sleep(AGAIN);
        }
    }

    /// Write `publication`, and whether it was written. A write refused
    /// once is asked again [`AGAIN`] later — on Windows a reader holding
    /// the file refuses the rename for the instant it reads — and only one
    /// that is still refused a round later is a failure: audited once,
    /// asked again every round, and said when it publishes again.
    fn write(&mut self, publication: &Publication) -> bool {
        let text = publication.to_toml();
        let written = xmip_observe::publication::write_atomic(&self.path, &text);
        self.board.post(text);
        match written {
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

/// The board the operate listener answers from, and the service it tells
/// when an act is taken there, so the service publishes it at once.
struct Telling {
    board: Arc<Board>,
    tell: Sender<Told>,
}

impl Published for Telling {
    fn read(&self) -> (u64, String) {
        self.board.read()
    }

    fn wait(&self, after: u64, within: Duration, stopped: &dyn Fn() -> bool) -> u64 {
        self.board.wait(after, within, stopped)
    }

    fn wake(&self) {
        self.board.wake();
    }

    fn acted(&self) {
        let _ = self.tell.send(Told::Acted);
    }
}
