//! Transport implementations that need nothing outside the standard library.
//!
//! Direction-neutral, per ADR-0010: one protocol, one implementation, and the
//! artifact decides whether it receives or sends. HTTP is the same protocol
//! whether Xmip is listening or calling, which is why the receive and send
//! sides are two methods on one trait rather than two repositories.
//!
//! Shaped to mirror XmipTransportVtable in include/xmip_module.h so that moving
//! an implementation across the C boundary later is mechanical rather than a
//! redesign.

use std::fs;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream, UdpSocket};
use std::path::PathBuf;
use std::time::Duration;

/// Which directions an implementation supports.
///
/// Mirrors XMIP_DIR_RECEIVE and XMIP_DIR_SEND.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Directions(u32);

impl Directions {
    pub const RECEIVE: Directions = Directions(1);
    pub const SEND: Directions = Directions(2);
    pub const BOTH: Directions = Directions(3);

    /// True when this implementation can receive.
    pub fn receives(self) -> bool {
        self.0 & 1 != 0
    }

    /// True when this implementation can send.
    pub fn sends(self) -> bool {
        self.0 & 2 != 0
    }
}

/// One Stream as it arrived, with where it came from.
///
/// origin_uri is historical fact and never changes, per ADR-0013. It says where
/// the bytes came from, not where they are now.
#[derive(Debug, Clone)]
pub struct Arrived {
    pub origin_uri: String,
    pub bytes: Vec<u8>,
}

/// A transport failure, carrying the one fact resilience needs.
///
/// retryable mirrors XMIP_IS_RETRYABLE: it is a property of the failure, not of
/// the call site, so xmip-core-resilience can decide without knowing which
/// implementation produced it.
#[derive(Debug)]
pub struct TransportError {
    pub message: String,
    pub retryable: bool,
}

impl std::fmt::Display for TransportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let kind = if self.retryable {
            "retryable"
        } else {
            "not retryable"
        };
        write!(f, "{} ({})", self.message, kind)
    }
}

impl std::error::Error for TransportError {}

/// Classify an I/O failure.
///
/// A blip is retryable; a missing file or a refused permission is not. Getting
/// this wrong is how a platform either gives up too early or retries forever.
fn classify(context: &str, error: &std::io::Error) -> TransportError {
    use std::io::ErrorKind;
    let retryable = matches!(
        error.kind(),
        ErrorKind::Interrupted
            | ErrorKind::WouldBlock
            | ErrorKind::TimedOut
            | ErrorKind::ConnectionReset
            | ErrorKind::ConnectionAborted
            | ErrorKind::ConnectionRefused
    );
    TransportError {
        message: format!("{context}: {error}"),
        retryable,
    }
}

pub type Result<T> = std::result::Result<T, TransportError>;

/// One protocol, both directions.
pub trait Transport {
    /// The standard token, as it appears in a repository name.
    fn name(&self) -> &'static str;

    /// Which directions this implementation actually supports.
    fn directions(&self) -> Directions;

    /// Take whatever has arrived. Returns an empty vector when nothing has.
    fn receive(&self) -> Result<Vec<Arrived>>;

    /// Deliver bytes to a target expressed in this protocol's own terms.
    fn send(&self, target: &str, bytes: &[u8]) -> Result<()>;
}

// ---------------------------------------------------------------------------
// file
// ---------------------------------------------------------------------------

/// Streams that arrive as files in a directory.
///
/// The polled case: nothing is pushed to Xmip, Xmip goes and looks. Identity is
/// therefore implied by the Receive Location rather than presented by a caller.
pub struct FileTransport {
    root: PathBuf,
}

impl FileTransport {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        FileTransport { root: root.into() }
    }
}

impl Transport for FileTransport {
    fn name(&self) -> &'static str {
        "file"
    }

    fn directions(&self) -> Directions {
        Directions::BOTH
    }

    fn receive(&self) -> Result<Vec<Arrived>> {
        let entries = match fs::read_dir(&self.root) {
            Ok(entries) => entries,
            // A drop directory that does not exist yet is not a failure.
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(e) => return Err(classify("reading the drop directory", &e)),
        };

        let mut arrived = Vec::new();
        for entry in entries {
            let entry = entry.map_err(|e| classify("listing the drop directory", &e))?;
            let path = entry.path();
            if !path.is_file() {
                continue;
            }
            let bytes = fs::read(&path).map_err(|e| classify("reading a dropped file", &e))?;
            arrived.push(Arrived {
                origin_uri: format!("file:///{}", path.display()),
                bytes,
            });
        }
        Ok(arrived)
    }

    fn send(&self, target: &str, bytes: &[u8]) -> Result<()> {
        let path = self.root.join(target);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|e| classify("creating the send directory", &e))?;
        }
        fs::write(&path, bytes).map_err(|e| classify("writing the sent file", &e))
    }
}

// ---------------------------------------------------------------------------
// tcp
// ---------------------------------------------------------------------------

/// Streams that arrive over a TCP connection, one Stream per connection.
///
/// The pushed case: a caller connects, so a transport-level identity exists.
pub struct TcpTransport {
    bind: String,
    read_timeout: Option<Duration>,
}

impl TcpTransport {
    pub fn new(bind: impl Into<String>) -> Self {
        TcpTransport {
            bind: bind.into(),
            read_timeout: None,
        }
    }

    /// Bind and report the address actually assigned.
    ///
    /// Binding to port 0 lets the operating system choose, which is what a test
    /// wants and what an operator never does.
    pub fn bind(&self) -> Result<(TcpListener, String)> {
        let listener =
            TcpListener::bind(&self.bind).map_err(|e| classify("binding the listener", &e))?;
        let local = listener
            .local_addr()
            .map_err(|e| classify("reading the bound address", &e))?;
        Ok((listener, local.to_string()))
    }

    /// Take one connection from an already-bound listener.
    pub fn accept_one(&self, listener: &TcpListener) -> Result<Arrived> {
        let (mut stream, peer) = listener
            .accept()
            .map_err(|e| classify("accepting a connection", &e))?;
        if let Some(timeout) = self.read_timeout {
            stream
                .set_read_timeout(Some(timeout))
                .map_err(|e| classify("setting the read timeout", &e))?;
        }
        let mut bytes = Vec::new();
        stream
            .read_to_end(&mut bytes)
            .map_err(|e| classify("reading the connection", &e))?;
        Ok(Arrived {
            origin_uri: format!("tcp://{peer}"),
            bytes,
        })
    }
}

impl Transport for TcpTransport {
    fn name(&self) -> &'static str {
        "tcp"
    }

    fn directions(&self) -> Directions {
        Directions::BOTH
    }

    fn receive(&self) -> Result<Vec<Arrived>> {
        let (listener, _) = self.bind()?;
        Ok(vec![self.accept_one(&listener)?])
    }

    fn send(&self, target: &str, bytes: &[u8]) -> Result<()> {
        let mut stream =
            TcpStream::connect(target).map_err(|e| classify("connecting to the peer", &e))?;
        stream
            .write_all(bytes)
            .map_err(|e| classify("writing to the peer", &e))?;
        stream
            .flush()
            .map_err(|e| classify("flushing to the peer", &e))
    }
}

// ---------------------------------------------------------------------------
// udp
// ---------------------------------------------------------------------------

/// Streams that arrive as datagrams. One datagram is one Stream.
///
/// There is no reply channel and no delivery guarantee, which makes it the
/// clearest case of a transport that cannot answer: a Contract failure here is
/// audited and nothing more.
pub struct UdpTransport {
    bind: String,
    max_datagram: usize,
}

impl UdpTransport {
    pub fn new(bind: impl Into<String>) -> Self {
        UdpTransport {
            bind: bind.into(),
            max_datagram: 65_507,
        }
    }
}

impl Transport for UdpTransport {
    fn name(&self) -> &'static str {
        "udp"
    }

    fn directions(&self) -> Directions {
        Directions::BOTH
    }

    fn receive(&self) -> Result<Vec<Arrived>> {
        let socket = UdpSocket::bind(&self.bind).map_err(|e| classify("binding the socket", &e))?;
        let mut buffer = vec![0u8; self.max_datagram];
        let (read, peer) = socket
            .recv_from(&mut buffer)
            .map_err(|e| classify("receiving a datagram", &e))?;
        buffer.truncate(read);
        Ok(vec![Arrived {
            origin_uri: format!("udp://{peer}"),
            bytes: buffer,
        }])
    }

    fn send(&self, target: &str, bytes: &[u8]) -> Result<()> {
        let socket =
            UdpSocket::bind("0.0.0.0:0").map_err(|e| classify("binding the sending socket", &e))?;
        socket
            .send_to(bytes, target)
            .map_err(|e| classify("sending a datagram", &e))?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn scratch(label: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock before epoch")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("xmip-{label}-{}-{nanos}", std::process::id()));
        fs::create_dir_all(&dir).expect("creating the scratch directory");
        dir
    }

    #[test]
    fn file_transport_declares_both_directions() {
        let t = FileTransport::new(std::env::temp_dir());
        assert!(t.directions().receives());
        assert!(t.directions().sends());
        assert_eq!(t.name(), "file");
    }

    #[test]
    fn file_receive_is_empty_when_the_directory_is_absent() {
        let t = FileTransport::new(std::env::temp_dir().join("xmip-definitely-not-here"));
        assert!(t
            .receive()
            .expect("an absent directory is not a failure")
            .is_empty());
    }

    #[test]
    fn file_round_trip_carries_bytes_and_origin() {
        let dir = scratch("file-round-trip");
        let t = FileTransport::new(&dir);

        t.send("order-1001.edi", b"ISA*00*").expect("sending");
        let arrived = t.receive().expect("receiving");

        assert_eq!(arrived.len(), 1);
        assert_eq!(arrived[0].bytes, b"ISA*00*");
        assert!(arrived[0].origin_uri.starts_with("file:///"));
        assert!(arrived[0].origin_uri.contains("order-1001.edi"));

        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn tcp_round_trip_carries_bytes_and_peer() {
        let t = TcpTransport::new("127.0.0.1:0");
        let (listener, address) = t.bind().expect("binding");

        let sender = std::thread::spawn(move || {
            let s = TcpTransport::new("127.0.0.1:0");
            s.send(&address, b"hello over tcp").expect("sending");
        });

        let arrived = t.accept_one(&listener).expect("accepting");
        sender.join().expect("the sending thread panicked");

        assert_eq!(arrived.bytes, b"hello over tcp");
        assert!(arrived.origin_uri.starts_with("tcp://127.0.0.1:"));
    }

    #[test]
    fn a_missing_file_is_not_retryable() {
        let error = classify(
            "reading",
            &std::io::Error::new(std::io::ErrorKind::NotFound, "no such file"),
        );
        assert!(!error.retryable);
    }

    #[test]
    fn a_refused_connection_is_retryable() {
        let error = classify(
            "connecting",
            &std::io::Error::new(std::io::ErrorKind::ConnectionRefused, "refused"),
        );
        assert!(error.retryable);
    }
}
