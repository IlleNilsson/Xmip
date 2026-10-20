//! `xmip-service` started in a console over loopback, as an operating
//! system or a terminal starts it, and held to what it does (ADR-0018,
//! amendments 2026-09-28 and 2026-09-30). What every test here starts it
//! with is here once; each test is in the file named for what it proves:
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
//! - `told.rs`: an order is acted on the moment it is left, within about a
//!   millisecond beyond what it carries, and a service nothing tells uses
//!   next to no processor.
//! - `accepted.rs`: a Receive Location terminating TLS with the node's
//!   `[provision.receive]` certificate accepts a Stream from the Party its
//!   `accept.party` names, through the build's own identity technologies,
//!   and refuses and audits one whose certificate names another.
//! - `carried.rs`: the getting-started node — roles executing and storage —
//!   carries a file dropped in its drop directory, accepted by the
//!   circumstance, to a file of the same name in its send directory, whole,
//!   audited, with Xmip's own work measured against the millisecond rule —
//!   alone.
//!
//! A test that measures how long Xmip takes — `carried.rs`, `told.rs` —
//! takes the machine whole ([`alone`]); every other shares it ([`sharing`]),
//! so what is measured is Xmip's work and not its neighbors'.
//!
//! Every Message is received and settled. Each reaches the first gate with
//! what its transport observed, and the build's `ip` identifier claims its
//! peer on the transport layer, passed. Where the Receive Location's
//! configuration declares no `accept`, it accepts nothing: every Message is
//! refused at authentication, by name, counted, and audited with the claim
//! it carried.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::sync::{PoisonError, RwLock, RwLockReadGuard, RwLockWriteGuard};
use std::time::{Duration, Instant};

use xmip_net::fixture::unheld;
use xmip_observe::{Act, Noun, Order};
use xmip_transport::Transport;
use xmip_transport_tcp::TcpTransport;

const MESSAGES: u64 = 50;

/// The machine the tests here run on: shared by those that only prove what
/// a node does, taken whole by one that measures how long it takes.
static MACHINE: RwLock<()> = RwLock::new(());

/// The machine, shared with every other test that shares it, for as long
/// as the guard is held.
fn sharing() -> RwLockReadGuard<'static, ()> {
    MACHINE.read().unwrap_or_else(PoisonError::into_inner)
}

/// The machine, no other test of this program running beside it, for as
/// long as the guard is held.
fn alone() -> RwLockWriteGuard<'static, ()> {
    MACHINE.write().unwrap_or_else(PoisonError::into_inner)
}

/// The Loopback Application, as its section of the node's configuration.
const APPLICATION: &str = r#"
[[xmip_applications]]
name = "Loopback"

[[xmip_applications.receive_ports]]
name = "Loopback"

[[xmip_applications.receive_locations]]
name = "In"
receive_port = "Loopback"
interaction = "data-transfer"
depth = "light"

[[xmip_applications.send_ports]]
name = "Out"

[[xmip_applications.subscriptions]]
id = "onward"
destination = { send-port = "Out" }
filter = "xmip.transport.mechanism = 'circumstance'"
"#;

/// The test cluster, read once: a publication's poll asks for its node.
fn test_cluster() -> &'static xmip_configure::fixture::TestCluster {
    static CLUSTER: std::sync::OnceLock<xmip_configure::fixture::TestCluster> =
        std::sync::OnceLock::new();
    CLUSTER.get_or_init(xmip_configure::fixture::test_cluster)
}

/// The node the service runs as: the test cluster's first node, by name.
fn node_name() -> String {
    test_cluster().node(0).name.clone()
}

/// The node the service runs as, by its scope.
fn node_scope() -> String {
    test_cluster().node_scope(0)
}

/// Who leaves an order: the test cluster's operator.
fn operator() -> String {
    format!("{}-operator", test_cluster().name)
}

/// The test cluster's first node takes both ends: a tcp Receive Location
/// on `receive` and a tcp Send Port to `far`. Its Location waits a tenth
/// of a second per receive, which is what bounds the drain. It declares the
/// storage role, so it keeps Xmip Storage itself; its data — its own
/// Storage node, its keys, its orders — is in `data` beside the
/// configuration.
fn node(receive: &str, far: &str) -> String {
    let cluster = &test_cluster().name;
    let node = node_name();
    format!(
        r#"roles = "executing, storage"

[service]
name = "xmip-{node}"
cluster_name = "{cluster}"
node_name = "{node}"
data = "data"

[[applications]]
name = "Loopback"

[[applications.receive_locations]]
name = "In"
node = "{node}"
start = true
transport = "xmip-core-transport-tcp"
address = "{receive}"
[applications.receive_locations.settings]
timeout = "100ms"

[[applications.send_ports]]
name = "Out"
node = "{node}"
start = true
transport = "xmip-core-transport-tcp"
address = "{far}"
{APPLICATION}"#
    )
}

/// The service's stdout, line by line, on a channel.
fn lines(child: &mut Child) -> Receiver<String> {
    let stdout = child.stdout.take().expect("piped");
    let (said, lines) = mpsc::channel();
    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if said.send(line).is_err() {
                return;
            }
        }
    });
    lines
}

/// The first line containing `words`, within `bound`.
fn heard(lines: &Receiver<String>, words: &str, bound: Duration) -> String {
    let deadline = Instant::now() + bound;
    loop {
        let left = deadline.saturating_duration_since(Instant::now());
        match lines.recv_timeout(left) {
            Ok(line) if line.contains(words) => return line,
            Ok(_) => {}
            Err(error) => panic!("never said '{words}': {error}"),
        }
    }
}

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

/// The process's exit, within `bound`.
fn exited(child: Child, bound: Duration) -> ExitStatus {
    let (done, exit) = mpsc::channel();
    let mut child = child;
    std::thread::spawn(move || {
        let _ = done.send(child.wait());
    });
    exit.recv_timeout(bound)
        .expect("it exits within the bound")
        .expect("its status")
}

/// Stop it the way a service manager does on Linux and macOS.
#[cfg(unix)]
fn stop(child: &Child) {
    let sent = Command::new("kill")
        .args(["-TERM", &child.id().to_string()])
        .status()
        .expect("kill runs");
    assert!(sent.success(), "SIGTERM sent");
}

/// Press Ctrl+Break in its console: the console stop that reaches one
/// process group alone, where Ctrl+C reaches every process on the console
/// and is ignored by a group of its own. Sending a console control event is
/// a call into kernel32 no safe Rust crate makes, and this estate writes no
/// unsafe outside the files it lists (ADR-0050), so PowerShell makes it: it
/// leaves its own console, attaches to the service's and raises the event
/// in the service's group.
#[cfg(windows)]
fn stop(child: &Child) {
    let script = format!(
        "$k = Add-Type -Name Console -Namespace XmipStop -PassThru -MemberDefinition '\
         [DllImport(\"kernel32.dll\")] public static extern bool FreeConsole(); \
         [DllImport(\"kernel32.dll\")] public static extern bool AttachConsole(uint p); \
         [DllImport(\"kernel32.dll\")] public static extern bool GenerateConsoleCtrlEvent(uint e, uint g);'; \
         [void]$k::FreeConsole(); \
         if (-not $k::AttachConsole({pid})) {{ exit 3 }}; \
         if (-not $k::GenerateConsoleCtrlEvent(1, {pid})) {{ exit 4 }}; exit 0",
        pid = child.id()
    );
    let sent = Command::new("pwsh")
        .args(["-NoProfile", "-NonInteractive", "-Command", &script])
        .status()
        .expect("pwsh runs");
    assert!(sent.success(), "Ctrl+Break pressed: {sent}");
}

/// A console of its own that nobody sees, and on Windows a process group of
/// its own, so the console stop reaches the service alone.
fn spawned(configuration: &Path, directory: &Path) -> Child {
    let mut command = Command::new(env!("CARGO_BIN_EXE_xmip-service"));
    command
        .args(["--configuration", configuration.to_str().expect("UTF-8")])
        .args(["--console", "--purpose", "test"])
        .env("XMIP_AUDIT_DIRECTORY", directory.join("audit"))
        .env("XMIP_PROCESS_DIRECTORY", directory.join("process"))
        .stdout(Stdio::piped());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NEW_PROCESS_GROUP: u32 = 0x0000_0200;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        command.creation_flags(CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW);
    }
    command.spawn().expect("xmip-service starts")
}

/// Ends the service where the test failed before it did, so a failing test
/// leaves nothing running and nothing holding its output open.
struct Ending(Option<u32>);

impl Drop for Ending {
    fn drop(&mut self) {
        if let Some(pid) = self.0 {
            let pid = pid.to_string();
            let _ = if cfg!(windows) {
                Command::new("taskkill").args(["/F", "/PID", &pid]).status()
            } else {
                Command::new("kill").args(["-KILL", &pid]).status()
            };
        }
    }
}

/// The node's configuration in `directory`, its local operate endpoint —
/// which always starts — named for the directory, so tests running at once
/// never meet on `xmip-<node>`. `[operate]` is its last table: a test adds
/// a key to it by adding a line.
fn written(directory: &Path, receive: &str) -> PathBuf {
    std::fs::create_dir_all(directory).expect("a directory");
    let path = directory.join(format!("{}.toml", node_name()));
    let text = format!(
        "{}\n[operate]\nlocal = \"{}\"\n",
        node(receive, &unheld().to_string()),
        endpoint(directory)
    );
    std::fs::write(&path, text).expect("writes");
    path
}

/// The local endpoint the node configured in `directory` is called.
fn endpoint(directory: &Path) -> String {
    let name = directory.file_name().and_then(|name| name.to_str());
    name.expect("a directory of its own").to_string()
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

/// Leave `act` on the Subscription `onward` where the node takes orders.
fn order(directory: &Path, act: Act) {
    Order {
        node: node_scope(),
        noun: Noun::Subscription,
        target: "onward".to_string(),
        act,
        who: operator(),
    }
    .leave(&directory.join("data").join("orders"))
    .expect("the order is left");
}

mod accepted;
mod carried;
mod operate;
mod publication;
mod stop;
mod told;
