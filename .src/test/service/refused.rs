//! `xmip-service` refusing a node, as every test here that needs one
//! refused hears it: what it says on stderr, and its exit code, 2. Placed
//! here once, beside `started.rs` and apart from it, since the timing
//! program `measured` shares `started.rs` and refuses nothing.

use super::*;

/// The scheme of a transport technology that is no feature of the root
/// crate, `xmip-core-transport-smb`'s.
pub(crate) const UNLINKED: &str = "smb://";

/// How long a refusal may take: a node refused never accepts work, so one
/// still running after this was not refused, and is killed.
const REFUSING: Duration = Duration::from_secs(30);

/// What the service says on stderr refusing the node at `configuration`,
/// which must exit 2 within [`REFUSING`]; one that does not is killed and
/// the test fails saying so, never waits on it.
pub(crate) fn refused(configuration: &Path, directory: &Path) -> String {
    let mut child = Command::new(env!("CARGO_BIN_EXE_xmip-service"))
        .args([
            "--configuration",
            configuration.to_str().expect("UTF-8"),
            "--console",
        ])
        .env("XMIP_AUDIT_DIRECTORY", directory.join("audit"))
        .env("XMIP_PROCESS_DIRECTORY", directory.join("process"))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .expect("runs");
    let mut stderr = child.stderr.take().expect("its error output");
    let reading = std::thread::spawn(move || {
        let mut said = String::new();
        let _ = std::io::Read::read_to_string(&mut stderr, &mut said);
        said
    });
    let deadline = Instant::now() + REFUSING;
    let status = loop {
        if let Some(status) = child.try_wait().expect("asks") {
            break status;
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            panic!(
                "the node at {} was not refused: still running after {REFUSING:?}",
                configuration.display()
            );
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    let said = reading.join().expect("read");
    assert_eq!(status.code(), Some(2), "{said}");
    said
}
