//! `xmip-service` started in a console over loopback, as an operating
//! system or a terminal starts it: what every test of both programs that
//! start it — `xmip-service` and `xmip-service-measured` — starts, tells,
//! hears and stops it with, here once.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::time::{Duration, Instant};

use xmip_net::fixture::unheld;
use xmip_observe::{Act, Noun, Order};
use xmip_runtime::directory_watch::DirectoryWatch;

/// The Loopback Application, as its section of the node's configuration.
pub(crate) const APPLICATION: &str = r#"
[[xmip_applications]]
name = "Loopback"

[[xmip_applications.receive_ports]]
name = "Loopback"

[[xmip_applications.receive_locations]]
name = "In"
receive_port = "Loopback"
depth = "light"

[[xmip_applications.send_ports]]
name = "Out"

[[xmip_applications.subscriptions]]
id = "onward"
destination = { send-port = "Out" }
filter = "xmip.transport.mechanism = 'circumstance'"
"#;

/// The test cluster, read once: a publication's poll asks for its node.
pub(crate) fn test_cluster() -> &'static xmip_configure::fixture::TestCluster {
    static CLUSTER: std::sync::OnceLock<xmip_configure::fixture::TestCluster> =
        std::sync::OnceLock::new();
    CLUSTER.get_or_init(xmip_configure::fixture::test_cluster)
}

/// The node the service runs as: the test cluster's first node, by name.
pub(crate) fn node_name() -> String {
    test_cluster().node(0).name.clone()
}

/// The node the service runs as, by its scope.
pub(crate) fn node_scope() -> String {
    test_cluster().node_scope(0)
}

/// Who leaves an order: the test cluster's operator.
pub(crate) fn operator() -> String {
    format!("{}-operator", test_cluster().name)
}

/// The test cluster's first node takes both ends: a tcp Receive Location
/// on `receive` and a tcp Send Port to `far`. Its Location waits a tenth
/// of a second per receive, which is what bounds the drain. It declares the
/// storage role, so it keeps Xmip Storage itself; its data — its own
/// Storage node, its keys, its orders — is in `data` beside the
/// configuration.
pub(crate) fn node(receive: &str, far: &str) -> String {
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
address = "tcp://{receive}"
[applications.receive_locations.settings]
timeout = "100ms"

[[applications.send_ports]]
name = "Out"
node = "{node}"
address = "tcp://{far}"
{APPLICATION}"#
    )
}

/// The service's stdout, line by line, on a channel.
pub(crate) fn lines(child: &mut Child) -> Receiver<String> {
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
pub(crate) fn heard(lines: &Receiver<String>, words: &str, bound: Duration) -> String {
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

/// The process's exit, within `bound`.
pub(crate) fn exited(child: Child, bound: Duration) -> ExitStatus {
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
pub(crate) fn stop(child: &Child) {
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
pub(crate) fn stop(child: &Child) {
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
pub(crate) fn spawned(configuration: &Path, directory: &Path) -> Child {
    let mut command = Command::new(env!("CARGO_BIN_EXE_xmip-service"));
    command
        .args(["--configuration", configuration.to_str().expect("UTF-8")])
        .args(["--console", "--purpose", "test"])
        .env("XMIP_AUDIT_DIRECTORY", directory.join("audit"))
        .env("XMIP_PROCESS_DIRECTORY", directory.join("process"))
        // Its input held open for as long as the child is, which a test
        // ends to stop it (`console.rs`); Ctrl+Break is what these press.
        .stdin(Stdio::piped())
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
pub(crate) struct Ending(pub(crate) Option<u32>);

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
pub(crate) fn written(directory: &Path, receive: &str) -> PathBuf {
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
pub(crate) fn endpoint(directory: &Path) -> String {
    let name = directory.file_name().and_then(|name| name.to_str());
    name.expect("a directory of its own").to_string()
}

/// Leave `act` on the Subscription `onward` where the node takes orders.
pub(crate) fn order(directory: &Path, act: Act) {
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

/// `directory` watched: a word on the channel each time it changes, until
/// the watch is dropped.
pub(crate) fn watched(directory: &Path) -> (Receiver<()>, DirectoryWatch) {
    let (tell, told) = mpsc::channel();
    let watch = DirectoryWatch::spawn(directory, move || {
        let _ = tell.send(());
    })
    .expect("watched");
    (told, watch)
}

/// When `holds` first held, asked at once and again each time the
/// directory behind `changed` changes; `None` where it did not by
/// `deadline`.
pub(crate) fn told(
    changed: &Receiver<()>,
    deadline: Instant,
    holds: impl Fn() -> bool,
) -> Option<Instant> {
    loop {
        if holds() {
            return Some(Instant::now());
        }
        let left = deadline.checked_duration_since(Instant::now())?;
        if changed.recv_timeout(left).is_err() {
            return holds().then(Instant::now);
        }
    }
}
