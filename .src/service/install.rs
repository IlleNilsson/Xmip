//! `--install` and `--uninstall`: what a package runs to lay a node out and
//! register its Xmip Service, and to remove the service again (ADR-0015,
//! amendment 2026-10-13). Every package — the MSI, the `.deb` and `.rpm`,
//! the macOS `.pkg` — and a person unpacking the portable archive run these
//! two, so the layout, the starter and the registration are written here
//! once and in no package's own script.
//!
//! `--install`, with the cluster's `xmip.toml` at `--configuration`:
//!
//! 1. writes a starter `xmip.toml` there, where there is none: the cluster
//!    `--cluster` names, the node `--node` names, offline (ADR-0045); its
//!    local operate endpoint needs no line, for it always starts, named
//!    `xmip-<node>` as its service is (ADR-0014, amendments 2026-10-13);
//! 2. slices the node's configuration, `xmip-node.toml` beside it, where
//!    there is none — `xmip-core-configure`'s one slicing;
//! 3. makes the layout's `modules` and `logs` beside `config`, the node's
//!    data directory and the audit directory under it (ADR-0015 clause 10);
//! 4. registers the node's Xmip Service — `definition.rs`'s, which
//!    `--definition` prints — to start with the machine, and starts it.
//!
//! A configuration already there is the operator's and is never written
//! over. `--uninstall`, with the node's configuration at `--configuration`
//! as `--definition` takes it, stops that node's service, waiting for its
//! drain, and removes it; it deletes no configuration, no data and no audit
//! (ADR-0040). Both
//! need the elevation registering needs (ADR-0018, Open): a package
//! installs elevated, and a person without it is refused in the service
//! manager's words.

use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

use xmip_audit::file_sink::DIRECTORY_VARIABLE;
use xmip_audit::program_audit::ProgramAudit;
use xmip_core::ExecutionPhase;
use xmip_runtime::registration::{REFUSED, ServiceDefinition, node_service_name};

use crate::arguments::Arguments;
use crate::definition::{self, text};
use crate::run;

/// The node's configuration, sliced beside its cluster's `xmip.toml`.
pub const NODE_FILE: &str = "xmip-node.toml";

/// The installed layout's folders beside `config` that nothing else makes
/// (ADR-0015 clause 10): `data` is the node configuration's to say, and
/// `bin` the package's.
const LAYOUT: [&str; 2] = ["modules", "logs"];

/// Install, or refuse in words.
pub fn install(audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    ended(audit, "install", installed(audit, arguments))
}

/// Uninstall, or refuse in words.
pub fn uninstall(audit: &ProgramAudit, arguments: &Arguments) -> ExitCode {
    ended(audit, "uninstall", uninstalled(audit, arguments))
}

fn ended(audit: &ProgramAudit, action: &str, outcome: Result<String, String>) -> ExitCode {
    match outcome {
        Ok(said) => {
            println!("OK: {said}");
            run::record(audit, action, ExecutionPhase::Finished, &[("said", &said)]);
            ExitCode::SUCCESS
        }
        Err(problem) => {
            run::fail(audit, action, &format!("xmip-service: {problem}"));
            ExitCode::from(REFUSED)
        }
    }
}

fn installed(audit: &ProgramAudit, arguments: &Arguments) -> Result<String, String> {
    let (node, cluster) = match (&arguments.node, &arguments.cluster) {
        (Some(node), Some(cluster)) => (node.as_str(), cluster.as_str()),
        _ => return Err("--install needs --node and --cluster".to_string()),
    };
    let cluster_file = PathBuf::from(&arguments.configuration);
    let directory = cluster_file
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .to_path_buf();
    run::record(audit, "install", ExecutionPhase::Begin, &[("node", node)]);
    std::fs::create_dir_all(&directory).map_err(|error| said(&directory, &error))?;

    if !cluster_file.exists() {
        write(&cluster_file, &starter(cluster, node))?;
    }
    let node_file = directory.join(NODE_FILE);
    if !node_file.exists() {
        let source =
            std::fs::read_to_string(&cluster_file).map_err(|error| said(&cluster_file, &error))?;
        write(&node_file, &xmip_configure::slice(&source, node)?)?;
    }

    if let Some(root) = directory.parent() {
        for folder in LAYOUT {
            let folder = root.join(folder);
            std::fs::create_dir_all(&folder).map_err(|error| said(&folder, &error))?;
        }
    }
    let (configured, service) = definition::node_service(&node_file)?;
    for (name, value) in &service.environment {
        if name == DIRECTORY_VARIABLE {
            std::fs::create_dir_all(value).map_err(|error| said(Path::new(value), &error))?;
        }
    }
    register(&service, &configured)?;
    Ok(format!(
        "{} registered and started, configured by {}",
        service.name,
        text(&node_file)
    ))
}

fn uninstalled(audit: &ProgramAudit, arguments: &Arguments) -> Result<String, String> {
    let (document, _, _) =
        xmip_runtime::start::read(&arguments.configuration).map_err(|unread| unread.reason)?;
    let node = document.service.node_name;
    let name = node_service_name(&node);
    run::record(
        audit,
        "uninstall",
        ExecutionPhase::Begin,
        &[("service", &name)],
    );
    deregister(&name, &node)
}

/// The starter `xmip.toml` of a one-node cluster: what a package writes
/// where the machine has none of its own.
fn starter(cluster: &str, node: &str) -> String {
    let service = node_service_name(node);
    format!(
        "# The cluster's configuration, xmip.toml, as an Xmip package starts it:\n\
         # one node, offline, operated from this machine on its local endpoint,\n\
         # {service}, which always starts (ADR-0015, amendment 2026-10-13;\n\
         # ADR-0014, amendments 2026-10-13). The node's configuration,\n\
         # {NODE_FILE}, is sliced from this file; change this one, slice again\n\
         # (xmip-service --slice) and restart the service.\n\
         [service]\n\
         name = {service}\n\
         cluster_name = {cluster}\n\
         \n\
         [nodes.{node_key}.service]\n\
         online = false\n",
        service = quoted(&service),
        cluster = quoted(cluster),
        node_key = quoted(node),
    )
}

/// `text` as a TOML basic string.
fn quoted(text: &str) -> String {
    format!("\"{}\"", text.replace('\\', "\\\\").replace('"', "\\\""))
}

fn write(path: &Path, content: &str) -> Result<(), String> {
    std::fs::write(path, content).map_err(|error| said(path, &error))
}

fn said(path: &Path, error: &std::io::Error) -> String {
    format!("{}: {error}", path.display())
}

/// Run `program` with `arguments`; its own words when it fails, unless its
/// exit code is one of `fine`.
fn command(program: &str, arguments: &[String], fine: &[i32]) -> Result<(), String> {
    let output = Command::new(program)
        .args(arguments)
        .output()
        .map_err(|error| format!("cannot run {program}: {error}"))?;
    let code = output.status.code().unwrap_or(-1);
    if output.status.success() || fine.contains(&code) {
        return Ok(());
    }
    let words = String::from_utf8_lossy(&output.stdout).trim().to_string()
        + String::from_utf8_lossy(&output.stderr).trim();
    Err(format!(
        "{program} {} exited {code}: {words}",
        arguments.join(" ")
    ))
}

/// Register `service`, node `node`'s, with this platform's service manager
/// and start it.
#[cfg(windows)]
fn register(service: &ServiceDefinition, node: &str) -> Result<(), String> {
    use xmip_runtime::registration::{windows_service_arguments, windows_service_settings};
    use xmip_runtime::service_control::{Act, control};
    // 1073: the service exists already, as on a repair.
    command("sc.exe", &windows_service_arguments(service), &[1073])?;
    for (program, arguments) in windows_service_settings(service) {
        command(&program, &arguments, &[])?;
    }
    control(Act::Start, node).map(|_| ())
}

#[cfg(target_os = "linux")]
fn register(service: &ServiceDefinition, _: &str) -> Result<(), String> {
    let unit = format!("/etc/systemd/system/{}.service", service.name);
    write(
        Path::new(&unit),
        &xmip_runtime::registration::systemd_unit(service),
    )?;
    let unit_name = format!("{}.service", service.name);
    command("systemctl", &[String::from("daemon-reload")], &[])?;
    command(
        "systemctl",
        &[String::from("enable"), unit_name.clone()],
        &[],
    )?;
    // A restart starts a stopped unit and runs an upgraded program.
    command("systemctl", &[String::from("restart"), unit_name], &[])
}

#[cfg(target_os = "macos")]
fn register(service: &ServiceDefinition, _: &str) -> Result<(), String> {
    // The local endpoints' folder first, made now and at every boot.
    let run = format!("/Library/LaunchDaemons/{}.run.plist", service.name);
    write(
        Path::new(&run),
        &xmip_runtime::registration::launchd_run_directory(service),
    )?;
    let _ = command(
        "launchctl",
        &[
            String::from("bootout"),
            format!("system/{}.run", service.name),
        ],
        &[],
    );
    command(
        "launchctl",
        &[String::from("bootstrap"), String::from("system"), run],
        &[],
    )?;
    let plist = format!("/Library/LaunchDaemons/{}.plist", service.name);
    write(
        Path::new(&plist),
        &xmip_runtime::registration::launchd_plist(service),
    )?;
    // An upgrade finds the daemon loaded; launchd loads it again only after
    // it is out, and a daemon that was never loaded is not, which is fine.
    let _ = command(
        "launchctl",
        &[String::from("bootout"), format!("system/{}", service.name)],
        &[],
    );
    command(
        "launchctl",
        &[String::from("bootstrap"), String::from("system"), plist],
        &[],
    )
}

#[cfg(not(any(windows, target_os = "linux", target_os = "macos")))]
fn register(_: &ServiceDefinition, _: &str) -> Result<(), String> {
    Err("this platform has no service manager".to_string())
}

/// Stop the service named `name`, node `node`'s, waiting for its drain, and
/// remove it.
#[cfg(windows)]
fn deregister(name: &str, node: &str) -> Result<String, String> {
    use std::time::{Duration, Instant};
    use windows_service::service::{ServiceAccess, ServiceState};
    use windows_service::service_manager::{ServiceManager, ServiceManagerAccess};
    use xmip_runtime::service_control::{Act, control};

    /// The Service Control Manager's word for a service it does not have.
    const DOES_NOT_EXIST: i32 = 1060;
    /// How long a drain may take before the removal says so.
    const DRAIN: Duration = Duration::from_secs(60);

    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
        .map_err(|error| format!("the Service Control Manager: {error}"))?;
    let access = ServiceAccess::QUERY_STATUS | ServiceAccess::DELETE;
    let service = match manager.open_service(name, access) {
        Ok(service) => service,
        Err(windows_service::Error::Winapi(error))
            if error.raw_os_error() == Some(DOES_NOT_EXIST) =>
        {
            return Ok(format!("{name} is not registered; nothing to remove"));
        }
        Err(error) => return Err(format!("{name}: {error}")),
    };
    let state = |service: &windows_service::service::Service| {
        service
            .query_status()
            .map(|status| status.current_state)
            .map_err(|error| format!("{name}: {error}"))
    };
    if state(&service)? != ServiceState::Stopped {
        control(Act::Stop, node)?;
        let began = Instant::now();
        while state(&service)? != ServiceState::Stopped {
            if began.elapsed() > DRAIN {
                return Err(format!("{name} did not stop within {} s", DRAIN.as_secs()));
            }
            std::thread::sleep(Duration::from_millis(20));
        }
    }
    service
        .delete()
        .map_err(|error| format!("{name}: {error}"))?;
    Ok(format!(
        "{name} stopped and removed; its configuration and data are kept"
    ))
}

#[cfg(target_os = "linux")]
fn deregister(name: &str, _: &str) -> Result<String, String> {
    let unit = format!("/etc/systemd/system/{name}.service");
    if !Path::new(&unit).exists() {
        return Ok(format!("{name} is not registered; nothing to remove"));
    }
    command(
        "systemctl",
        &[
            String::from("disable"),
            String::from("--now"),
            format!("{name}.service"),
        ],
        &[],
    )?;
    std::fs::remove_file(&unit).map_err(|error| said(Path::new(&unit), &error))?;
    command("systemctl", &[String::from("daemon-reload")], &[])?;
    Ok(format!(
        "{name} stopped and removed; its configuration and data are kept"
    ))
}

#[cfg(target_os = "macos")]
fn deregister(name: &str, _: &str) -> Result<String, String> {
    let plist = format!("/Library/LaunchDaemons/{name}.plist");
    if !Path::new(&plist).exists() {
        return Ok(format!("{name} is not registered; nothing to remove"));
    }
    command(
        "launchctl",
        &[String::from("bootout"), format!("system/{name}")],
        &[],
    )?;
    std::fs::remove_file(&plist).map_err(|error| said(Path::new(&plist), &error))?;
    // The folder's daemon goes with it; the folder stays for other nodes.
    let run = format!("/Library/LaunchDaemons/{name}.run.plist");
    let _ = command(
        "launchctl",
        &[String::from("bootout"), format!("system/{name}.run")],
        &[],
    );
    let _ = std::fs::remove_file(&run);
    Ok(format!(
        "{name} stopped and removed; its configuration and data are kept"
    ))
}

#[cfg(not(any(windows, target_os = "linux", target_os = "macos")))]
fn deregister(_: &str, _: &str) -> Result<String, String> {
    Err("this platform has no service manager".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The starter slices for its node and reads as `xmip-service` reads a
    /// node's configuration, naming no operate listener.
    #[test]
    fn the_starter_slices_and_reads_as_the_service_reads_it() {
        let cluster = xmip_configure::fixture::test_cluster();
        let node = cluster.node(0).name.clone();
        let source = starter(&cluster.name, &node);

        let sliced = xmip_configure::slice(&source, &node).expect("slices");
        let directory = std::env::temp_dir().join(format!("xmip-starter-{}", std::process::id()));
        std::fs::create_dir_all(&directory).expect("a directory");
        let file = directory.join(NODE_FILE);
        std::fs::write(&file, &sliced).expect("written");
        let read = xmip_runtime::start::read(&text(&file));
        std::fs::remove_dir_all(&directory).expect("removed");

        let (document, _, _) = read.expect("reads");
        assert_eq!(document.service.node_name, node);
        assert_eq!(document.service.cluster_name, cluster.name);
        assert!(!document.service.online);
        // No [operate]: the local endpoint starts all the same, named as
        // the service is, and nothing else listens.
        assert!(document.operate.is_none());
        assert!(source.contains(&quoted(&node_service_name(&node))));
    }

    #[test]
    fn a_name_is_quoted_as_toml_says_it() {
        assert_eq!(quoted(r#"a"b\c"#), r#""a\"b\\c""#);
    }
}
