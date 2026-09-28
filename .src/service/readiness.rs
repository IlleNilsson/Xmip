//! Telling systemd the node's state: the unit is `Type=notify`
//! (`registration::systemd_unit`), so systemd reports the service started
//! only once the node accepts work — ADR-0018's ninth phase, not the
//! process's first instruction. The message is one datagram to the socket
//! systemd names in `NOTIFY_SOCKET`, as `sd_notify(3)` sends it. Anywhere else
//! — another platform, a console, a unit of another type — there is no
//! socket and nothing is sent.

/// The node accepts work.
pub fn ready() {
    notify("READY=1");
}

/// A stop arrived and the node drains.
pub fn stopping() {
    notify("STOPPING=1");
}

#[cfg(target_os = "linux")]
fn notify(state: &str) {
    if let Some(socket) = std::env::var_os("NOTIFY_SOCKET")
        && let Err(error) = notify_at(&socket.to_string_lossy(), state)
    {
        eprintln!("xmip-service: could not tell systemd {state}: {error}");
    }
}

/// Send `state` to the socket `socket` names: `@name` is an abstract
/// socket, anything else a path.
#[cfg(target_os = "linux")]
fn notify_at(socket: &str, state: &str) -> std::io::Result<()> {
    use std::os::linux::net::SocketAddrExt;
    use std::os::unix::net::{SocketAddr, UnixDatagram};

    let address = match socket.strip_prefix('@') {
        Some(name) => SocketAddr::from_abstract_name(name.as_bytes())?,
        None => SocketAddr::from_pathname(socket)?,
    };
    UnixDatagram::unbound()?.send_to_addr(state.as_bytes(), &address)?;
    Ok(())
}

#[cfg(not(target_os = "linux"))]
fn notify(_state: &str) {}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use std::os::unix::net::UnixDatagram;

    #[test]
    fn systemd_hears_each_state_on_the_socket_it_named() {
        let directory = std::env::temp_dir().join(format!("xmip-notify-{}", std::process::id()));
        std::fs::create_dir_all(&directory).expect("a directory");
        let path = directory.join("notify");
        let systemd = UnixDatagram::bind(&path).expect("binds");

        for state in ["READY=1", "STOPPING=1"] {
            super::notify_at(path.to_str().expect("UTF-8"), state).expect("sent");
            let mut heard = [0u8; 32];
            let length = systemd.recv(&mut heard).expect("hears");
            assert_eq!(&heard[..length], state.as_bytes());
        }
        std::fs::remove_dir_all(&directory).ok();
    }
}
