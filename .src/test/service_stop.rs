//! `xmip-service` started in a console over loopback, handed Messages, and
//! stopped the way a terminal or a service manager stops it: the console's
//! Ctrl+Break on Windows, SIGTERM on Linux and macOS. The stop drains the node and the
//! process exits 0, within a bound; it declared itself while it ran and
//! audited its start and its stop.
//!
//! A node keeps its runtime store where its configuration says, and a
//! Subscription an operator paused through an order is paused still after
//! the service is stopped and started again (ADR-0018, amendment
//! 2026-09-30).
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

#[test]
fn a_stop_drains_the_node_and_the_service_exits_zero() {
    let directory = std::env::temp_dir().join(format!("xmip-service-stop-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let receive = free_address();
    let configuration = written(&directory, &receive);

    let mut child = spawned(&configuration, &directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        "xmip:///C1/node/R1 accepts work",
        Duration::from_secs(10),
    );

    let declared = declarations(&directory);
    assert!(
        declared
            .iter()
            .any(|text| text.contains("location = \"xmip:///C1/node/R1\"")
                && text.contains("purpose = \"test\"")),
        "{declared:?}"
    );

    for message in 0..MESSAGES {
        deliver(&receive, format!("order {message}").as_bytes());
    }

    stop(&child);
    let asked = Instant::now();
    let stopped = heard(&said, "stopped by the console", Duration::from_secs(5));
    let status = exited(child, Duration::from_secs(5));
    let took = asked.elapsed();
    ending.0 = None;

    assert!(status.success(), "{status}");
    // The Location's own wait, a tenth of a second, bounds the drain.
    assert!(took < Duration::from_secs(2), "stopping took {took:?}");
    assert!(
        stopped.contains(&format!("received {MESSAGES}")),
        "{stopped}"
    );
    assert!(
        stopped.contains(&format!("refused {MESSAGES}")),
        "{stopped}"
    );
    assert!(
        declarations(&directory).is_empty(),
        "the declaration goes with it"
    );

    let audit =
        std::fs::read_to_string(directory.join("audit").join("audit.toml")).expect("it audited");
    for said in [
        "action = \"start\"",
        "action = \"stop\"",
        "\"by\" = \"the console\"",
        &format!("\"received\" = \"{MESSAGES}\""),
    ] {
        assert!(audit.contains(said), "{said} in {audit}");
    }
    let _ = std::fs::remove_dir_all(&directory);
}

#[test]
fn a_node_it_cannot_start_is_refused_with_exit_code_two() {
    let directory =
        std::env::temp_dir().join(format!("xmip-service-refused-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let configuration = written(&directory, &free_address());
    let text = std::fs::read_to_string(&configuration).expect("reads");
    std::fs::write(
        &configuration,
        text.replacen("xmip-core-transport-tcp", "xmip-core-transport-sftp", 1),
    )
    .expect("writes");

    let output = Command::new(env!("CARGO_BIN_EXE_xmip-service"))
        .args([
            "--configuration",
            configuration.to_str().expect("UTF-8"),
            "--console",
        ])
        .env("XMIP_AUDIT_DIRECTORY", directory.join("audit"))
        .env("XMIP_PROCESS_DIRECTORY", directory.join("process"))
        .output()
        .expect("runs");

    assert_eq!(output.status.code(), Some(2));
    let said = String::from_utf8_lossy(&output.stderr);
    assert!(said.contains("xmip-core-transport-sftp"), "{said}");
    assert!(declarations(&directory).is_empty());
    let _ = std::fs::remove_dir_all(&directory);
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

/// Start the service at `configuration`, act on its Subscription as each
/// of `acts` says, hearing each answer, and stop it the operating system's
/// way.
fn served(configuration: &Path, directory: &Path, acts: &[(Act, &str)]) {
    let mut child = spawned(configuration, directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        "keeps its store xmip-core-persist-rocksdb",
        Duration::from_secs(10),
    );
    heard(
        &said,
        &format!("{NODE} accepts work"),
        Duration::from_secs(10),
    );
    for (act, answer) in acts {
        order(directory, *act);
        heard(&said, answer, Duration::from_secs(2));
    }
    stop(&child);
    heard(&said, "stopped by the console", Duration::from_secs(5));
    assert!(exited(child, Duration::from_secs(5)).success());
    ending.0 = None;
}

#[test]
fn a_paused_subscription_is_paused_still_after_the_service_restarts() {
    let directory = std::env::temp_dir().join(format!("xmip-service-store-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let configuration = written(&directory, &free_address());

    served(
        &configuration,
        &directory,
        &[(Act::Pause, "Subscription 'onward' paused by C1-operator")],
    );
    assert!(
        directory.join("data").join("persistence-rocksdb").is_dir(),
        "the store is where the layout puts it"
    );
    served(
        &configuration,
        &directory,
        &[
            (Act::Pause, "Subscription 'onward' was already paused"),
            (
                Act::Resume,
                "Subscription 'onward' resumed by C1-operator; the 0 it held",
            ),
        ],
    );

    let audit =
        std::fs::read_to_string(directory.join("audit").join("audit.toml")).expect("it audited");
    for said in [
        "subscription.pause",
        "subscription.resume",
        "persistence-rocksdb",
    ] {
        assert!(audit.contains(said), "{said} in {audit}");
    }
    let _ = std::fs::remove_dir_all(&directory);
}

/// What the service says on stderr refusing the node at `configuration`,
/// which must exit 2.
fn refused(configuration: &Path, directory: &Path) -> String {
    let output = Command::new(env!("CARGO_BIN_EXE_xmip-service"))
        .args([
            "--configuration",
            configuration.to_str().expect("UTF-8"),
            "--console",
        ])
        .env("XMIP_AUDIT_DIRECTORY", directory.join("audit"))
        .env("XMIP_PROCESS_DIRECTORY", directory.join("process"))
        .output()
        .expect("runs");
    assert_eq!(output.status.code(), Some(2));
    String::from_utf8_lossy(&output.stderr).into_owned()
}

#[test]
fn a_store_the_build_did_not_link_or_that_does_not_open_is_refused() {
    let directory =
        std::env::temp_dir().join(format!("xmip-service-unstored-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let configuration = written(&directory, &free_address());
    let text = std::fs::read_to_string(&configuration).expect("reads");

    let unlinked = "[store]
engine = \"xmip-core-persist-lmdb\"
place = \"lmdb\"
";
    std::fs::write(
        &configuration,
        format!(
            "{text}
{unlinked}"
        ),
    )
    .expect("writes");
    let said = refused(&configuration, &directory);
    assert!(
        said.contains("'xmip-core-persist-lmdb', which this node was not built with"),
        "{said}"
    );

    // A file where the engine wants its directory.
    std::fs::write(directory.join("taken"), "not a store").expect("writes");
    std::fs::write(
        &configuration,
        format!(
            "{text}
[store]
place = \"taken\"
"
        ),
    )
    .expect("writes");
    let said = refused(&configuration, &directory);
    assert!(said.contains("did not open"), "{said}");
    assert!(declarations(&directory).is_empty());
    let audit =
        std::fs::read_to_string(directory.join("audit").join("audit.toml")).expect("it audited");
    assert!(audit.contains("xmip-core-persist-lmdb"), "{audit}");
    let _ = std::fs::remove_dir_all(&directory);
}
