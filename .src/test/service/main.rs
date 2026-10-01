//! `xmip-service` started in a console over loopback, as an operating
//! system or a terminal starts it, and held to what it does (ADR-0018,
//! amendments 2026-09-28 and 2026-09-30). What every test here starts it
//! with is here once; each test is in the file named for what it proves:
//!
//! - `stop.rs`: a stop drains the node and the process exits 0, within a
//!   bound, having declared and audited itself; a node it cannot start, or a
//!   store it cannot open, is refused with exit 2; a Subscription paused
//!   through an order is paused still after a restart.
//! - `publication.rs`: the node publishes its snapshot where it declares,
//!   read by observe's one reader; a pause left where the snapshot says the
//!   node takes orders shows paused in the next one; and the stop leaves it
//!   saying so.
//!
//! Every Message is received and settled. The build links no authenticator
//! and the configuration can name none yet, so the Receive Location accepts
//! nothing and every Message is refused at its gate, by name, and counted.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::time::{Duration, Instant};

use xmip_observe::{Act, Noun, Order};
use xmip_transport::Transport;
use xmip_transport_tcp::TcpTransport;

const MESSAGES: u64 = 50;

const APPLICATION: &str = r#"[application]
name = "Loopback"

[[receive_locations]]
name = "In"

[[send_ports]]
name = "Out"

[[subscriptions]]
id = "onward"
destination = { send-port = "Out" }
filter = "xmip.transport.mechanism = 'circumstance'"
"#;

/// Node C1-R1 takes both ends: a tcp Receive Location on `receive` and a
/// tcp Send Port to `far`. Its Location waits a tenth of a second per
/// receive, which is what bounds the drain. Its data — the runtime store,
/// its keys, its orders — is in `data` beside the configuration.
fn node(receive: &str, far: &str) -> String {
    format!(
        r#"[service]
name = "xmip-R1"
cluster_name = "C1"
node_name = "R1"
data = "data"

[[applications]]
name = "Loopback"
document = "loopback.application.toml"

[[applications.receive_locations]]
name = "In"
node = "R1"
start = true
transport = "xmip-core-transport-tcp"
address = "{receive}"
[applications.receive_locations.settings]
timeout = "100ms"

[[applications.send_ports]]
name = "Out"
node = "R1"
start = true
transport = "xmip-core-transport-tcp"
address = "{far}"
"#
    )
}

fn free_address() -> String {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("a free port");
    listener.local_addr().expect("its address").to_string()
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

fn written(directory: &Path, receive: &str) -> PathBuf {
    std::fs::create_dir_all(directory).expect("a directory");
    std::fs::write(directory.join("loopback.application.toml"), APPLICATION).expect("writes");
    let path = directory.join("R1.toml");
    std::fs::write(&path, node(receive, &free_address())).expect("writes");
    path
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

const NODE: &str = "xmip:///C1/node/R1";

/// Leave `act` on the Subscription `onward` where the node takes orders.
fn order(directory: &Path, act: Act) {
    Order {
        node: NODE.to_string(),
        noun: Noun::Subscription,
        target: "onward".to_string(),
        act,
        who: "C1-operator".to_string(),
    }
    .leave(&directory.join("data").join("orders"))
    .expect("the order is left");
}

mod publication;
mod stop;
