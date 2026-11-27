//! The far end of each transport this build links, standing in this test
//! as its own crate stands it (ADR-0051, the `Loopback` it implements): the
//! far end is Xmip (ADR-0028 clause 5), bound on this machine and waiting
//! for its one exchange; and how a Send Port names it, in the words a node's
//! configuration has, its address and its settings (`linked.rs`).
//!
//! The node is a process of its own, so only a far end another process
//! reaches is one: a socket on loopback, a named pipe, a database file. A
//! transport whose far end lives inside one process — a simulated bus, a
//! radio held in memory — is not linked, and README's *Transports* says why
//! for each. Two linked before are proven elsewhere: file by every test of
//! this program, and sftp by the System Tests' far ends.
//!
//! A far end that checks a secret — a broker's or a server's login, a
//! vendor's key, signature or token — checks one the test draws, which the
//! node presents from the secret its Send Port names (`secured.rs`).
//!
//! A Send Location that announces or answers — mDNS a service, SSDP a
//! device, DHCP a lease — sends what its protocol says in one datagram, and
//! its crate's loopback far end asks its sender back for a Stream in chunks
//! or plays the other side; its far end here is what hears that one
//! datagram (`announced.rs`), and the document it is sent is one its
//! protocol carries whole: TXT strings, a notification, options.
//!
//! A serial line's far end is a device on a pseudo-terminal, which a node
//! opens by its path as it opens a port (`terminal.rs`): one frame a serial
//! Send Location writes, or a HART, IO-Link or M-Bus master's Stream,
//! answered as the protocol's own crate answers it on the SDK's bus in
//! process, or a wireless M-Bus Location's, through the receiver stick its
//! own crate stands. Linux and macOS have one, Windows none.
//!
//! A CAN technology's and an Ethernet technology's far end is on a link of
//! the kernel's, an interface a test makes in a network namespace of its
//! own (`kernel.rs`), and is stood there, never in [`every`].
//!
//! A `LoRaWAN` Send Location's far end is a device behind a gateway pointed
//! at the node, its network server, over Semtech's UDP packet forwarder
//! protocol (`gateway.rs`): the node listens, and the far end reaches it.

use std::path::Path;
use std::time::Duration;

use xmip_transport::{Configured, FarEnd, Loopback};

mod announced;
#[cfg(feature = "transport-lorawan")]
mod gateway;
#[cfg(feature = "transport-sqlite")]
mod table;
mod terminal;

#[cfg(feature = "transport-sqlite")]
use table::Table;

/// What a far end takes where its protocol carries any bytes: one XML
/// document, short and plain, as every linked protocol carries it whole —
/// inside an MLLP block, a Peppol Standard Business Document, a Modbus
/// write, an IEC 104 ASDU.
pub(crate) const DOCUMENT: &str = "<probe><n>1</n>round-trip</probe>";

/// How long a far end waits for the node, and for each read of it: a bound
/// on the test, never on Xmip.
pub(crate) const BOUND: Duration = Duration::from_secs(20);

/// A value for a far end to check, never one written down: 32 bytes from
/// the operating system's random source, in base64, which an Azure account
/// key is and every other secret here may be.
pub(crate) fn drawn() -> String {
    xmip_codec::base64::encode(&xmip_codec::random::array::<32>())
}

/// One linked transport's far end, and the Send Port that reaches it.
pub(crate) struct Standing {
    /// The Send Port's name, the transport's own.
    pub(crate) name: &'static str,
    pub(crate) far: Box<dyn FarEnd>,
    /// The Send Location's address.
    pub(crate) address: String,
    /// Its settings, each a name and its value as TOML writes it.
    pub(crate) settings: Vec<(&'static str, String)>,
    /// Whether the far end hands what it took only once its connection is
    /// let go, which a node keeps in its pool until it stops.
    pub(crate) at_close: bool,
    /// What it is sent, and its far end takes: [`DOCUMENT`], or what its
    /// protocol carries whole where it carries a shape of its own.
    pub(crate) document: &'static str,
    /// The secret its Send Port names, and the value it holds, which its
    /// far end checks, where it checks one (`secured.rs`).
    pub(crate) secret: Option<(String, String)>,
}

impl Standing {
    /// `far`, reached at `address` with `settings`, each `{far}` in them its
    /// address.
    fn new(
        name: &'static str,
        far: Box<dyn FarEnd>,
        address: &str,
        settings: &[(&'static str, &str)],
        at_close: bool,
    ) -> Self {
        let reached = |text: &str| text.replace("{far}", far.address());
        let address = reached(address);
        let settings = settings
            .iter()
            .map(|(key, value)| (*key, reached(value)))
            .collect();
        Self {
            name,
            far,
            address,
            settings,
            at_close,
            document: DOCUMENT,
            secret: None,
        }
    }

    /// Sent `document` in place of [`DOCUMENT`].
    const fn sent(mut self, document: &'static str) -> Self {
        self.document = document;
        self
    }

    /// Its far end checking `value`, which its Send Port presents as the
    /// secret `linked.<name>`.
    fn secured(mut self, value: &str) -> Self {
        self.secret = Some((format!("linked.{}", self.name), value.to_string()));
        self
    }

    /// The file its document is dropped into the node as, which its
    /// Subscription takes by name: `probe.xml` for [`DOCUMENT`], which
    /// every far end taking it shares, and its own name else.
    pub(crate) fn file(&self) -> String {
        if self.document == DOCUMENT {
            "probe.xml".to_string()
        } else {
            format!("{}.probe", self.name)
        }
    }
}

/// `loopback`'s far end, waiting [`BOUND`]; none where this machine cannot
/// stand it, as the technology says (`Loopback::unavailable`): a Unix
/// domain socket on Windows.
fn stood<T: Loopback + Configured>(loopback: T) -> Option<Box<dyn FarEnd>> {
    if let Some(why) = loopback.unavailable() {
        println!("{}: not on this machine: {why}", loopback.name());
        return None;
    }
    Some(
        loopback
            .timing_out_after(BOUND)
            .far_end()
            .expect("the far end stands"),
    )
}

/// The far end `$loopback` stands where this build links `$feature`, its
/// Send Port `$name` at `$address` with the settings listed, each value a
/// TOML text or integer, written as it is listed; sent `$document` where
/// one is named, [`DOCUMENT`] else. A far end written `|$drawn| $loopback`
/// checks a value drawn for it ([`drawn`]), its Send Port's secret.
macro_rules! standing {
    ($all:ident, $feature:literal, $name:literal, |$drawn:ident| $loopback:expr,
     $($rest:tt)*) => {
        #[cfg(feature = $feature)]
        {
            let ($drawn, mut one) = (crate::far_ends::drawn(), Vec::new());
            standing! {one, $feature, $name, $loopback, $($rest)*}
            $all.extend(one.into_iter().map(|one: Standing| one.secured(&$drawn)));
        }
    };
    ($all:ident, $feature:literal, $name:literal, $loopback:expr, $address:literal,
     [$($key:literal = $value:literal),*], $at_close:literal) => {
        standing! {$all, $feature, $name, $loopback, $address, [$($key = $value),*],
        $at_close, crate::far_ends::DOCUMENT}
    };
    ($all:ident, $feature:literal, $name:literal, $loopback:expr, $address:literal,
     [$($key:literal = $value:literal),*], $at_close:literal, $document:expr) => {
        #[cfg(feature = $feature)]
        if let Some(far) = $loopback {
            let settings: &[(&'static str, &str)] = &[$(($key, stringify!($value))),*];
            let one = crate::far_ends::Standing::new($name, far, $address, settings, $at_close);
            $all.push(one.sent($document));
        }
    };
}

/// The far ends on a link of the kernel's, Linux's alone, which a test
/// stands in a network namespace of its own (`namespaced.rs`).
#[cfg(target_os = "linux")]
pub(crate) mod kernel;

/// The far ends that check the secret a node presents: the brokers' and
/// servers' that require a login, and the vendors'.
#[cfg(any(
    feature = "transport-activemq",
    feature = "transport-amqp",
    feature = "transport-aws-kinesis",
    feature = "transport-aws-s3",
    feature = "transport-aws-sns",
    feature = "transport-aws-sqs",
    feature = "transport-azure-blob",
    feature = "transport-azure-event-grid",
    feature = "transport-azure-event-hubs",
    feature = "transport-azure-service-bus",
    feature = "transport-ftp",
    feature = "transport-google-cloud-storage",
    feature = "transport-google-pub-sub",
    feature = "transport-rabbitmq",
    feature = "transport-smb"
))]
mod secured;

/// Every far end this build's linked transports have, in the order of their
/// names, and after them those checking a secret (`secured::every`); a
/// database file's under `directory`.
#[allow(
    clippy::too_many_lines,
    reason = "one far end a transport, each its few lines"
)]
pub(crate) fn every(
    #[cfg_attr(not(feature = "transport-sqlite"), allow(unused_variables))] directory: &Path,
) -> Vec<Standing> {
    let mut all = Vec::new();
    standing! {all, "transport-as2", "as2",
    stood(xmip_transport_as2::As2Transport::loopback()),
    "as2://{far}/as2", ["as2_id" = "Buyer", "to_party_id" = "Seller"], false}
    standing! {all, "transport-as4", "as4",
    stood(xmip_transport_as4::As4Transport::loopback()),
    "as4://{far}/msh", ["party_id" = "Xmip", "to_party_id" = "Xmip"], false}
    standing! {all, "transport-bacnet", "bacnet",
    stood(xmip_transport_bacnet::BacnetTransport::loopback()), "bacnet://{far}", [], false}
    standing! {all, "transport-coap", "coap",
    stood(xmip_transport_coap::CoapTransport::loopback()), "coap://{far}/probe", [], false}
    standing! {all, "transport-cotp", "cotp",
    stood(xmip_transport_cotp::CotpTransport::loopback()), "cotp://{far}", [], false}
    standing! {all, "transport-db2", "db2",
    stood(xmip_transport_db2::Db2Transport::loopback()),
    "db2://{far}/PROBE/PROBE/PAYLOAD", ["database" = "PROBE", "user" = "xmip"], false}
    standing! {all, "transport-dds", "dds",
    stood(xmip_transport_dds::DdsTransport::loopback()),
    "dds://127.0.0.1:0", ["locator" = "{far}"], false}
    standing! {all, "transport-dhcp", "dhcp", Some(announced::client()),
    "dhcp://{far}?xid=0x786d6970&mac=02:00:00:78:6d:69&type=offer", [], false,
    announced::LEASE}
    standing! {all, "transport-dicom", "dicom",
    stood(xmip_transport_dicom::DicomTransport::loopback()),
    "dicom://{far}", ["called" = "XMIP"], false}
    standing! {all, "transport-dnp3", "dnp3",
    stood(xmip_transport_dnp3::Dnp3Transport::loopback()),
    "dnp3://{far}", ["source" = 1, "destination" = 1024], false}
    standing! {all, "transport-dns", "dns",
    stood(xmip_transport_dns::DnsTransport::loopback()),
    "dns://{far}", ["zone" = "xmip.example.", "name" = "probe.xmip.example."], false}
    standing! {all, "transport-ethernet-ip", "ethernet-ip",
    stood(xmip_transport_ethernet_ip::EtherNetIpTransport::loopback()),
    "enip://{far}", [], true}
    standing! {all, "transport-hart", "hart", terminal::field_device(),
    "hart://{far}", ["device" = "0"], false}
    standing! {all, "transport-http", "http",
    stood(xmip_transport_http::HttpTransport::loopback()), "http://{far}/probe", [], false}
    standing! {all, "transport-ibm-mq", "ibm-mq",
    stood(xmip_transport_ibm_mq::IbmMqTransport::loopback()),
    "ibm-mq://{far}", ["queue_manager" = "QM1", "queue" = "ORDERS"], true}
    standing! {all, "transport-iec-60870-5-104", "iec-60870-5-104",
    stood(xmip_transport_iec_60870_5_104::Iec104Transport::loopback()),
    "iec104://{far}", [], true}
    standing! {all, "transport-iec-61850", "iec-61850",
    stood(xmip_transport_iec_61850::Iec61850Transport::loopback()),
    "iec61850://{far}", [], true}
    standing! {all, "transport-imap", "imap",
    stood(xmip_transport_imap::ImapTransport::loopback()),
    "imap://{far}", ["mailbox" = "INBOX", "user" = "probe"], false}
    standing! {all, "transport-io-link", "io-link", terminal::io_link_device(),
    "iolink://{far}", ["rate" = "com2"], false}
    standing! {all, "transport-kafka", "kafka",
    stood(xmip_transport_kafka::KafkaTransport::loopback()),
    "kafka://{far}", ["topic" = "probe"], false}
    standing! {all, "transport-knx", "knx",
    stood(xmip_transport_knx::KnxTransport::loopback()),
    "knx://{far}", ["local" = "127.0.0.1:0", "timeout" = "10s"], false}
    #[cfg(feature = "transport-lorawan")]
    all.push(gateway::device());
    standing! {all, "transport-m-bus", "m-bus", terminal::meter(),
    "mbus://{far}", ["meter" = 1], false}
    standing! {all, "transport-mariadb", "mariadb",
    stood(xmip_transport_mariadb::MariaDbTransport::loopback()),
    "mariadb://{far}/probe/inbox/payload", ["database" = "probe", "user" = "xmip"], false}
    standing! {all, "transport-mdns", "mdns", Some(announced::browser()),
    "mdns://{far}/Probe._xmip._tcp.local?port=8080", [], false, announced::SERVICE}
    standing! {all, "transport-mllp", "mllp",
    stood(xmip_transport_mllp::MllpTransport::loopback()), "mllp://{far}", [], false}
    standing! {all, "transport-modbus", "modbus",
    stood(xmip_transport_modbus::ModbusTransport::loopback()), "modbus://{far}", [], true}
    standing! {all, "transport-mqtt", "mqtt",
    stood(xmip_transport_mqtt::MqttTransport::loopback()),
    "mqtt://{far}", ["topic" = "probe"], false}
    standing! {all, "transport-msmq", "msmq",
    stood(xmip_transport_msmq::MsmqTransport::loopback()),
    "msmq://{far}/round-trip", ["host" = "xmip-test"], false}
    standing! {all, "transport-mssql", "mssql",
    stood(xmip_transport_mssql::MssqlTransport::loopback()),
    "mssql://{far}/probe/inbox/payload", ["database" = "probe", "user" = "xmip"], false}
    standing! {all, "transport-mysql", "mysql",
    stood(xmip_transport_mysql::MySqlTransport::loopback().with_password("")),
    "mysql://{far}/probe/inbox/payload", ["database" = "probe", "user" = "xmip"], false}
    standing! {all, "transport-named-pipe", "named-pipe",
    stood(xmip_transport_named_pipe::NamedPipeTransport::loopback()),
    "pipe://{far}", [], false}
    standing! {all, "transport-nats", "nats",
    stood(xmip_transport_nats::NatsTransport::loopback()),
    "nats://{far}", ["subject" = "probe"], false}
    standing! {all, "transport-nats-jetstream", "nats-jetstream",
    stood(xmip_transport_nats_jetstream::JetStreamTransport::loopback()),
    "nats-jetstream://{far}", ["subject" = "probe"], false}
    standing! {all, "transport-nfs", "nfs",
    stood(xmip_transport_nfs::NfsTransport::loopback()),
    "nfs://{far}", ["export" = "/probe"], false}
    standing! {all, "transport-opc-ua", "opc-ua",
    stood(xmip_transport_opc_ua::OpcUaTransport::loopback()),
    "opc.tcp://{far}/xmip#ns=2;s=Probe", [], false}
    standing! {all, "transport-oracle", "oracle",
    stood(xmip_transport_oracle::OracleTransport::loopback()),
    "oracle://{far}/XMIP/inbox/payload", ["service" = "XMIP", "user" = "xmip"], false}
    standing! {all, "transport-peppol", "peppol",
    stood(xmip_transport_peppol::PeppolTransport::loopback()),
    "peppol://{far}/as4",
    ["participant" = "0088:7300010000001", "party" = "0088:7300010000001"], false}
    standing! {all, "transport-postgresql", "postgresql",
    stood(xmip_transport_postgresql::PostgresTransport::loopback()),
    "postgresql://{far}/probe/inbox/payload", ["database" = "probe", "user" = "probe"],
    false}
    standing! {all, "transport-redis-streams", "redis-streams",
    stood(xmip_transport_redis_streams::RedisStreamsTransport::loopback()),
    "redis://{far}", ["stream" = "probe"], false}
    standing! {all, "transport-redpanda", "redpanda",
    stood(xmip_transport_redpanda::RedpandaTransport::loopback()),
    "redpanda://{far}", ["topic" = "probe"], false}
    standing! {all, "transport-s7comm", "s7comm",
    stood(xmip_transport_s7comm::S7Transport::loopback()),
    "s7comm://{far}", ["variable" = "DB1.DBB0"], true}
    standing! {all, "transport-secs-gem", "secs-gem",
    stood(xmip_transport_secs_gem::SecsGemTransport::loopback()),
    "secs-gem://{far}", [], true}
    standing! {all, "transport-serial", "serial", terminal::line(),
    "serial://{far}", ["baud" = 9600], false}
    standing! {all, "transport-smtp", "smtp",
    stood(xmip_transport_smtp::SmtpTransport::loopback()),
    "smtp://{far}", ["from" = "xmip@example.com", "to" = "round-trip@example.com"], true}
    standing! {all, "transport-snmp", "snmp",
    stood(xmip_transport_snmp::SnmpTransport::loopback()),
    "snmp+set://{far}/1.3.6.1.4.1.0.1.0", [], false}
    standing! {all, "transport-sqlite", "sqlite",
    Some(Table::under(directory)), "sqlite://{far}", [], false}
    standing! {all, "transport-ssdp", "ssdp", Some(announced::control_point()),
    "ssdp://{far}", [], false, announced::DEVICE}
    standing! {all, "transport-syslog", "syslog",
    stood(xmip_transport_syslog::SyslogTransport::loopback()),
    "syslog+tcp://{far}", ["carrier" = "tcp", "hostname" = "xmip-test"], false}
    standing! {all, "transport-tcp", "tcp",
    stood(xmip_transport_tcp::TcpTransport::loopback()), "tcp://{far}", [], false}
    standing! {all, "transport-udp", "udp",
    stood(xmip_transport_udp::UdpTransport::loopback()), "udp://{far}", [], false}
    standing! {all, "transport-unix-socket", "unix-socket",
    stood(xmip_transport_unix_socket::UnixSocketTransport::loopback()),
    "unix://{far}", [], false}
    standing! {all, "transport-webdav", "webdav",
    stood(xmip_transport_webdav::WebDavTransport::loopback()),
    "webdav://{far}/probe.bin", [], false}
    standing! {all, "transport-websocket", "websocket",
    stood(xmip_transport_websocket::WebSocketTransport::loopback()),
    "ws://{far}/probe", [], false}
    standing! {all, "transport-wireless-m-bus", "wireless-m-bus", terminal::receiver(),
    "wmbus://{far}", ["manufacturer" = "XMP", "ident" = 12345678, "version" = 1, "medium" = 7],
    false}
    #[cfg(any(
        feature = "transport-activemq",
        feature = "transport-amqp",
        feature = "transport-aws-kinesis",
        feature = "transport-aws-s3",
        feature = "transport-aws-sns",
        feature = "transport-aws-sqs",
        feature = "transport-azure-blob",
        feature = "transport-azure-event-grid",
        feature = "transport-azure-event-hubs",
        feature = "transport-azure-service-bus",
        feature = "transport-ftp",
        feature = "transport-google-cloud-storage",
        feature = "transport-google-pub-sub",
        feature = "transport-rabbitmq",
        feature = "transport-smb"
    ))]
    secured::every(&mut all);
    all
}
