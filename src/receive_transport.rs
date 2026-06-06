#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiveTransport {
    Tcp,
    Udp,
    FileSystem,
    RemoteFile,
    Broker,
    Schedule,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiveProtocolHint {
    Http,
    Soap,
    Rest,
    RawTcp,
    RawUdp,
    File,
    Queue,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiveBoundary {
    pub transport: ReceiveTransport,
    pub protocol_hint: ReceiveProtocolHint,
}

impl ReceiveBoundary {
    pub fn unknown() -> Self {
        Self {
            transport: ReceiveTransport::Unknown,
            protocol_hint: ReceiveProtocolHint::Unknown,
        }
    }
}
