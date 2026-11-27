//! The technologies this build of `xmip-service` linked, handed to the node
//! it starts (`xmip_runtime::linked::Linked`). The site it was built for
//! decides which (ADR-0015, amendment 2026-10-01): each is a feature of this
//! crate, set by `Build-XmipService` from the site's target, roles and
//! technologies, and the node takes only what its
//! configuration names; a Location naming one this build left out is refused
//! as the node starts.
//!
//! Transports, and the engines and key stores of an embedded Storage node:
//! a node declaring the storage role, its own Storage node, opens Xmip
//! Storage over `RocksDB`,
//! the runtime database's one engine (ADR-0015 and ADR-0018, amendments
//! 2026-10-01), and `SQLite`, the administration database's, which the
//! storage role builds (`deploy/profile/role/storage.toml`), sealed under a
//! key store this build carries; one built without either engine, or
//! naming a key store it left out, is refused as it starts
//! (`xmip_runtime::storage`).
//!
//! The identify technologies whose claim a linked transport carries, with
//! no configuration (ADR-0019 clause 5, ADR-0050 section 3): a TLS peer
//! certificate, a bearer token's subject, an API key, a Basic credential's
//! user, the socket peer. Every Stream reaches the first gate with what its
//! transport observed and its headers, and its claim is recorded with its
//! layer and how it was established.
//!
//! The authenticate and authorize technologies, each set up by what the
//! node's configuration says (ADR-0068): `circumstance`, a drop folder's
//! implied identity, which every build carries, for a Receive Location
//! whose `accept.mechanism` names it (the owner, 2026-10-19); `mutual-tls`,
//! which records what a transport's handshake proved, for a Receive
//! Location whose `accept.mechanism` names it — the handshake terminated by
//! tcp with the node's `[provision.receive]` certificate; and `location`,
//! which admits at each Receive Location the node starts what that
//! Location's `accept` declares it takes, its Parties narrowed at
//! authentication (ADR-0019 clause 1), and at each Send Location the node
//! starts what reached it (the owner, 2026-10-19). A Stream any gate
//! refuses is refused, and the attempt refused at authentication is
//! audited with the claim it carried (ADR-0013 clause 1).
//!
//! The route technologies, each the source a Subscription filter's prefix
//! names (ADR-0046): `content`, where the site links it, reads a path into
//! the Message's first section in the path languages the build links —
//! `edi`, a segment, element and component of an EDIFACT or X12
//! interchange — so a filter routes by what the document says,
//! `"content:edi:UNH/2/1" = 'ORDERS'`, as the real world does (the owner,
//! 2026-11-10; ADR-0046, amendment 2026-11-11). A property with no prefix is
//! the context's, which every node reads.
//!
//! The retry guard, with the `resilience` feature every role that sends
//! carries: each Send Port stating `retry` is given it as the node starts,
//! and it decides whether and when a send that failed is tried again
//! (ADR-0048, amendment 2026-11-14).

use xmip_audit::program_audit::ProgramAudit;
use xmip_authenticate::Authenticator;
#[cfg(feature = "identify")]
use xmip_identify::TransportIdentifier;
use xmip_runtime::linked::{Linked, LinkedEngine, LinkedKeyStore, LinkedTransport, LocationPolicy};

/// What this build carries, and the audit an operator's act on a
/// Subscription is recorded in.
pub fn linked(audit: &ProgramAudit) -> Linked {
    Linked {
        transports: transports(),
        sources: sources(),
        engine: engine(),
        administration: administration(),
        key_stores: key_stores(),
        #[cfg(feature = "identify")]
        transport_identifiers: transport_identifiers(),
        authenticators: authenticators(),
        location_policies: location_policies(),
        #[cfg(feature = "resilience")]
        retry: Some(retry),
        audit: Some(audit.clone()),
        ..Linked::default()
    }
}

/// The retry guard this build carries, as a Send Port's `retry` is built:
/// `tries` in all, `backoff` after each that failed, flat (ADR-0048,
/// amendment 2026-11-14).
#[cfg(feature = "resilience")]
fn retry(tries: u32, backoff: std::time::Duration) -> Box<dyn xmip_resilience::Guard> {
    Box::new(xmip_resilience_retry::Retry::new(tries, backoff))
}

/// The authenticators this build carries, each taken where a Receive
/// Location the node starts accepts its mechanism: `circumstance` in every
/// build, since every node infers a circumstance where nothing was
/// presented (ADR-0019 clause 7); `broker` in every build, which answers
/// for the sender a broker delivered a message as (ADR-0019, amendment
/// 2026-10-31); and those the site linked.
#[allow(
    unused_mut,
    clippy::vec_init_then_push,
    reason = "each push after the first is a feature this build may leave out"
)]
pub fn authenticators() -> Vec<Box<dyn Authenticator>> {
    let mut authenticators: Vec<Box<dyn Authenticator>> = Vec::new();
    authenticators.push(Box::new(xmip_authenticate::Circumstance));
    authenticators.push(Box::new(xmip_authenticate::Broker));
    #[cfg(feature = "authenticate-mutual-tls")]
    authenticators.push(Box::new(xmip_authenticate_mutual_tls::Verifier::new()));
    authenticators
}

/// The policies this build sets up from the Locations a node starts.
#[allow(
    unused_mut,
    clippy::vec_init_then_push,
    reason = "each push is a feature this build may leave out"
)]
pub fn location_policies() -> Vec<LocationPolicy> {
    let mut policies: Vec<LocationPolicy> = Vec::new();
    #[cfg(feature = "authorize-location")]
    policies.push(location);
    policies
}

/// The `location` policy (ADR-0050 section 5): each Receive Location the
/// node starts admits what its `accept` declares it takes — the mechanisms
/// it authenticates, narrowed to the Parties it names — and anyone those
/// authenticate; and each Send Location the node starts admits what reached
/// it (the owner, 2026-10-19: *the `location` policy also admits each Send
/// Location the node starts, as it admits Receive Locations*). A Location's
/// hours and the identities it admits by value have no key in a node's
/// configuration yet.
#[cfg(feature = "authorize-location")]
fn location(started: xmip_runtime::linked::Started<'_>) -> Box<dyn xmip_authorize::Authorizer> {
    use xmip_authorize_location::{Admission, LocationPolicy};
    let receive = started
        .receive
        .iter()
        .map(|gate| Admission::receive(&gate.location));
    let send = started
        .send
        .iter()
        .map(|location| Admission::send(&location.name));
    Box::new(
        receive
            .chain(send)
            .fold(LocationPolicy::new(), |policy, admission| {
                policy.admit(admission.anyone())
            }),
    )
}

/// The route technologies this build carries: `content` where the site
/// links it, over the path languages the build links — the source and its
/// languages made where they are made once,
/// `xmip_route_content::ContentSource::linked`.
#[allow(
    unused_mut,
    clippy::vec_init_then_push,
    reason = "each push is a feature this build may leave out"
)]
pub fn sources() -> Vec<Box<dyn xmip_route::Source>> {
    let mut sources: Vec<Box<dyn xmip_route::Source>> = Vec::new();
    #[cfg(feature = "route-content")]
    sources.push(Box::new(xmip_route_content::ContentSource::linked()));
    sources
}

/// The runtime database's engine, where this build carries it.
#[allow(
    clippy::unnecessary_wraps,
    reason = "a build without persist-rocksdb carries no engine"
)]
pub fn engine() -> Option<LinkedEngine> {
    cfg_select! {
        feature = "persist-rocksdb" => {
            Some(LinkedEngine::new(xmip_configure::store::ENGINE, |place| {
                Ok(Box::new(xmip_persist_rocksdb::RocksDb::open(place)?))
            }))
        }
        _ => None,
    }
}

/// The administration database's engine, where this build carries it.
#[allow(
    clippy::unnecessary_wraps,
    reason = "a build without persist-sqlite carries no administration database"
)]
pub fn administration() -> Option<LinkedEngine> {
    cfg_select! {
        feature = "persist-sqlite" => Some(LinkedEngine::new(
            xmip_runtime::storage::ADMINISTRATION,
            |place| Ok(Box::new(xmip_persist_sqlite::Sqlite::open(place)?)),
        )),
        _ => None,
    }
}

/// The key stores this build carries: the platform's (ADR-0063 clause 4),
/// each where its crate is more than empty.
#[allow(
    unused_mut,
    clippy::vec_init_then_push,
    reason = "each push is a platform or a feature this build may leave out"
)]
pub fn key_stores() -> Vec<LinkedKeyStore> {
    let mut stores = Vec::new();
    #[cfg(all(feature = "secret", windows))]
    stores.push(LinkedKeyStore::new("xmip-core-secret-dpapi", |keys| {
        Box::new(xmip_secret::Held::new(xmip_secret_dpapi::Dpapi::new(keys)))
    }));
    #[cfg(all(feature = "secret", unix))]
    stores.push(LinkedKeyStore::new("xmip-core-secret-file", |keys| {
        Box::new(xmip_secret::Held::new(xmip_secret_file::KeyFile::new(keys)))
    }));
    // The keychain keeps its keys as items of one service, not in a
    // directory: `keys` is not its to read.
    #[cfg(all(feature = "secret", target_os = "macos"))]
    stores.push(LinkedKeyStore::new("xmip-core-secret-keychain", |_| {
        Box::new(xmip_secret::Held::new(xmip_secret_keychain::Keychain::new(
            "Xmip",
        )))
    }));
    stores
}

/// The first gate's technologies this build carries, in the order the gate
/// asks them: the first claim an arrival carries is the one authenticated
/// (`xmip_runtime::arrival`), so a credential the sender presented comes
/// before the peer it connected from, and the certificate a TLS handshake
/// verified before a credential sent inside the connection, and the sender
/// a broker delivered a message as before the peer address.
#[allow(
    unused_mut,
    clippy::vec_init_then_push,
    reason = "each push is a feature this build may leave out"
)]
#[cfg(feature = "identify")]
pub fn transport_identifiers() -> Vec<Box<dyn TransportIdentifier>> {
    let mut identifiers: Vec<Box<dyn TransportIdentifier>> = Vec::new();
    #[cfg(feature = "identify-certificate")]
    identifiers.push(Box::new(xmip_identify_certificate::Certificate));
    #[cfg(feature = "identify-jwt")]
    identifiers.push(Box::new(xmip_identify_jwt::Jwt::bearer()));
    #[cfg(feature = "identify-api-key")]
    identifiers.push(Box::new(xmip_identify_api_key::ApiKey::default()));
    #[cfg(feature = "identify-username")]
    identifiers.push(Box::new(xmip_identify_username::Username::default()));
    identifiers.push(Box::new(xmip_identify::broker::Broker));
    #[cfg(feature = "identify-ip")]
    identifiers.push(Box::new(xmip_identify_ip::IpIdentifier::new()));
    identifiers
}

/// Each transport this build carries, by the feature that links it.
macro_rules! linked {
    ($($feature:literal => $technology:ty),* $(,)?) => {{
        let mut transports: Vec<LinkedTransport> = Vec::new();
        $(
            #[cfg(feature = $feature)]
            transports.push(LinkedTransport::of::<$technology>());
        )*
        transports
    }};
}

/// The transports this build carries, each by its own declaration, in the
/// order of their names: every one written whose far end a node in a
/// process of its own reaches, each proven carrying a file through the
/// service (`.src/test/service/linked.rs`), a serial line's through a
/// pseudo-terminal, which Linux and macOS have, a vendor's presenting
/// the secret its Location names, and `LoRaWAN`'s through a gateway's packet
/// forwarder over UDP (ADR-0015, amendments 2026-11-24, 2026-11-25 and
/// 2026-11-27); and after them those on a link of the kernel's, Bluetooth's
/// among them ([`kernel_transports`]).
#[allow(
    unused_mut,
    clippy::vec_init_then_push,
    reason = "each push is a feature this build may leave out"
)]
pub fn transports() -> Vec<LinkedTransport> {
    let mut transports = linked![
        "transport-activemq" => xmip_transport_activemq::ActiveMqTransport,
        "transport-amqp" => xmip_transport_amqp::AmqpTransport,
        "transport-as2" => xmip_transport_as2::As2Transport,
        "transport-as4" => xmip_transport_as4::As4Transport,
        "transport-aws-kinesis" => xmip_transport_aws_kinesis::KinesisTransport,
        "transport-aws-s3" => xmip_transport_aws_s3::S3Transport,
        "transport-aws-sns" => xmip_transport_aws_sns::SnsTransport,
        "transport-aws-sqs" => xmip_transport_aws_sqs::SqsTransport,
        "transport-azure-blob" => xmip_transport_azure_blob::AzureBlobTransport,
        "transport-azure-event-grid" => xmip_transport_azure_event_grid::EventGridTransport,
        "transport-azure-event-hubs" => xmip_transport_azure_event_hubs::EventHubsTransport,
        "transport-azure-service-bus" => xmip_transport_azure_service_bus::ServiceBusTransport,
        "transport-bacnet" => xmip_transport_bacnet::BacnetTransport,
        "transport-coap" => xmip_transport_coap::CoapTransport,
        "transport-cotp" => xmip_transport_cotp::CotpTransport,
        "transport-db2" => xmip_transport_db2::Db2Transport,
        "transport-dds" => xmip_transport_dds::DdsTransport,
        "transport-dhcp" => xmip_transport_dhcp::DhcpTransport,
        "transport-dicom" => xmip_transport_dicom::DicomTransport,
        "transport-dnp3" => xmip_transport_dnp3::Dnp3Transport,
        "transport-dns" => xmip_transport_dns::DnsTransport,
        "transport-ethernet-ip" => xmip_transport_ethernet_ip::EtherNetIpTransport,
        "transport-file" => xmip_transport_file::FileTransport,
        "transport-ftp" => xmip_transport_ftp::FtpTransport,
        "transport-google-cloud-storage" => xmip_transport_google_cloud_storage::GcsTransport,
        "transport-google-pub-sub" => xmip_transport_google_pub_sub::PubSubTransport,
        "transport-hart" => xmip_transport_hart::HartTransport,
        "transport-http" => xmip_transport_http::HttpTransport,
        "transport-ibm-mq" => xmip_transport_ibm_mq::IbmMqTransport,
        "transport-iec-60870-5-104" => xmip_transport_iec_60870_5_104::Iec104Transport,
        "transport-iec-61850" => xmip_transport_iec_61850::Iec61850Transport,
        "transport-imap" => xmip_transport_imap::ImapTransport,
        "transport-io-link" => xmip_transport_io_link::IoLinkTransport,
        "transport-kafka" => xmip_transport_kafka::KafkaTransport,
        "transport-knx" => xmip_transport_knx::KnxTransport,
        "transport-lorawan" => xmip_transport_lorawan::LorawanTransport,
        "transport-m-bus" => xmip_transport_m_bus::MBusTransport,
        "transport-mariadb" => xmip_transport_mariadb::MariaDbTransport,
        "transport-mdns" => xmip_transport_mdns::MdnsTransport,
        "transport-mllp" => xmip_transport_mllp::MllpTransport,
        "transport-modbus" => xmip_transport_modbus::ModbusTransport,
        "transport-mqtt" => xmip_transport_mqtt::MqttTransport,
        "transport-msmq" => xmip_transport_msmq::MsmqTransport,
        "transport-mssql" => xmip_transport_mssql::MssqlTransport,
        "transport-mysql" => xmip_transport_mysql::MySqlTransport,
        "transport-named-pipe" => xmip_transport_named_pipe::NamedPipeTransport,
        "transport-nats" => xmip_transport_nats::NatsTransport,
        "transport-nats-jetstream" => xmip_transport_nats_jetstream::JetStreamTransport,
        "transport-nfs" => xmip_transport_nfs::NfsTransport,
        "transport-opc-ua" => xmip_transport_opc_ua::OpcUaTransport,
        "transport-oracle" => xmip_transport_oracle::OracleTransport,
        "transport-peppol" => xmip_transport_peppol::PeppolTransport,
        "transport-pop3" => xmip_transport_pop3::Pop3Transport,
        "transport-postgresql" => xmip_transport_postgresql::PostgresTransport,
        "transport-rabbitmq" => xmip_transport_rabbitmq::RabbitMqTransport,
        "transport-redis-streams" => xmip_transport_redis_streams::RedisStreamsTransport,
        "transport-redpanda" => xmip_transport_redpanda::RedpandaTransport,
        "transport-s7comm" => xmip_transport_s7comm::S7Transport,
        "transport-secs-gem" => xmip_transport_secs_gem::SecsGemTransport,
        "transport-serial" => xmip_transport_serial::SerialTransport,
        "transport-sftp" => xmip_transport_sftp::SftpTransport,
        "transport-smb" => xmip_transport_smb::SmbTransport,
        "transport-smtp" => xmip_transport_smtp::SmtpTransport,
        "transport-snmp" => xmip_transport_snmp::SnmpTransport,
        "transport-sqlite" => xmip_transport_sqlite::SqliteTransport,
        "transport-ssdp" => xmip_transport_ssdp::SsdpTransport,
        "transport-syslog" => xmip_transport_syslog::SyslogTransport,
        "transport-tcp" => xmip_transport_tcp::TcpTransport,
        "transport-udp" => xmip_transport_udp::UdpTransport,
        "transport-unix-socket" => xmip_transport_unix_socket::UnixSocketTransport,
        "transport-webdav" => xmip_transport_webdav::WebDavTransport,
        "transport-websocket" => xmip_transport_websocket::WebSocketTransport,
        "transport-wireless-m-bus" => xmip_transport_wireless_m_bus::WirelessMBusTransport,
    ];
    transports.extend(kernel_transports());
    transports
}

/// The transports that reach a link of the kernel's, in the order of their
/// names: a Bluetooth controller's L2CAP sockets, a CAN interface (can-bus's
/// `socketcan`) and what rides on it, and an Ethernet interface's raw socket
/// (ethernet's `packet`) and what rides on it, which Linux alone has. Each
/// CAN and Ethernet one is proven by a node in a user and network namespace
/// of the test's own, on interfaces it makes there
/// (`.src/test/service/namespaced.rs`; ADR-0015, amendment 2026-11-25), and
/// Bluetooth by the node of `.src/test/service/linked.rs`, from the first of
/// two virtual controllers to a far end on the second (amendment
/// 2026-11-27). Elsewhere none: a CAN Location there would open a bus
/// inside the node alone, and a Bluetooth one reach only a radio in it.
#[allow(
    unused_mut,
    clippy::vec_init_then_push,
    reason = "each push is a feature this build may leave out"
)]
fn kernel_transports() -> Vec<LinkedTransport> {
    cfg_select! {
        target_os = "linux" => linked![
            "transport-bluetooth" => xmip_transport_bluetooth::BluetoothTransport,
            "transport-can-bus" => xmip_transport_can_bus::CanTransport,
            "transport-canopen" => xmip_transport_canopen::CanOpenTransport,
            "transport-ethercat" => xmip_transport_ethercat::EtherCatTransport,
            "transport-ethernet" => xmip_transport_ethernet::EthernetTransport,
            "transport-iso-tp" => xmip_transport_iso_tp::IsoTpTransport,
            "transport-j1939" => xmip_transport_j1939::J1939Transport,
            "transport-obd-ii" => xmip_transport_obd_ii::ObdTransport,
            "transport-profinet" => xmip_transport_profinet::ProfinetTransport,
            "transport-uds" => xmip_transport_uds::UdsTransport,
        ],
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_transport_is_linked_by_the_schemes_a_location_is_entered_with() {
        let linked = Linked {
            transports: transports(),
            ..Linked::default()
        };
        let names: Vec<&str> = linked
            .transports
            .iter()
            .map(LinkedTransport::technology)
            .collect();

        #[cfg(feature = "transport-tcp")]
        assert!(names.contains(&"xmip-core-transport-tcp"), "{names:?}");
        assert!(
            names
                .iter()
                .all(|name| name.starts_with("xmip-core-transport-"))
        );
        assert!(
            linked
                .transports
                .iter()
                .all(|one| !one.schemes().is_empty()),
            "every transport is chosen by a scheme"
        );
        assert_eq!(linked.scheme_problems(), Vec::<String>::new());
    }

    #[cfg(feature = "identify-ip")]
    #[test]
    fn the_first_gate_reads_the_peer_after_every_credential() {
        let mechanisms: Vec<String> = transport_identifiers()
            .iter()
            .map(|identifier| identifier.mechanism().name().to_string())
            .collect();

        assert_eq!(mechanisms.last().map(String::as_str), Some("ip"));
    }

    #[cfg(feature = "authenticate-mutual-tls")]
    #[test]
    fn a_handshake_the_transport_verified_is_authenticated_by_mutual_tls() {
        let mechanisms: Vec<String> = authenticators()
            .iter()
            .map(|authenticator| authenticator.mechanism().name().to_string())
            .collect();

        assert!(
            mechanisms.contains(&"mutual-tls".to_string()),
            "{mechanisms:?}"
        );
    }

    #[cfg(all(feature = "authorize-location", feature = "authenticate"))]
    #[test]
    fn each_location_the_node_starts_admits_what_its_gates_authenticated() {
        use xmip_authorize::{Action, Attempt};
        use xmip_context::{Alignment, AuthenticatedIdentity, IdentityFacts, Verified};
        use xmip_runtime::linked::Started;
        use xmip_runtime::receiving::ReceiveGate;

        let gates = [ReceiveGate::new(
            "In",
            xmip_authenticate::Acceptance::closed(),
        )];
        let node = xmip_configure::parse_toml(
            "[service]\nname = \"n\"\ncluster_name = \"c\"\nnode_name = \"d\"\n\n\
             [[send_locations]]\nname = \"Out\"\naddress = \"a\"\n",
        )
        .expect("reads");
        let started = Started {
            receive: &gates,
            send: &node.send_locations,
        };
        let policy = location_policies()
            .into_iter()
            .map(|build| build(started))
            .find(|policy| policy.name() == "location")
            .expect("the location policy");
        let facts = IdentityFacts::evaluate(
            Alignment::None,
            AuthenticatedIdentity::new(
                xmip_core::mechanism::mutual_tls(),
                "CN=anyone.example",
                xmip_core::Established::Passed,
                Verified::Proven,
            ),
            None,
        );

        assert!(
            policy
                .decide(&facts, &Attempt::now(Action::Receive, "In"))
                .is_some_and(|decision| decision.allowed())
        );
        assert_eq!(
            policy.decide(&facts, &Attempt::now(Action::Receive, "Elsewhere")),
            None
        );
        assert!(
            policy
                .decide(&facts, &Attempt::now(Action::Send, "Out"))
                .is_some_and(|decision| decision.allowed()),
            "the owner, 2026-10-19: a Send Location the node starts is admitted"
        );
        assert_eq!(
            policy.decide(&facts, &Attempt::now(Action::Send, "Elsewhere")),
            None
        );
    }

    #[cfg(all(feature = "route-content", feature = "path-edi"))]
    #[test]
    fn a_filter_reads_what_an_edifact_document_says_where_the_build_links_content() {
        let sources = sources();
        let names: Vec<&str> = sources.iter().map(|source| source.technology()).collect();
        assert_eq!(names, ["content"]);
        assert!(
            sources[0].compile("edi:UNH/2/1").is_ok(),
            "the message type"
        );
        assert!(
            sources[0].compile("dot:order.id").is_err(),
            "a language the build left out is refused"
        );
    }

    #[cfg(feature = "resilience")]
    #[test]
    fn a_send_ports_retry_is_the_retry_guard_this_build_links() {
        use std::time::Duration;
        use xmip_resilience::{Attempt, Decision};

        let failed = |number| Attempt {
            number,
            elapsed: Duration::ZERO,
            failure: Some(xmip_core::Failure::retryable("the far end is down")),
        };
        // As the node is handed it (`Linked::retry`): two tries, 5 s apart.
        let built: xmip_runtime::linked::RetryGuard = retry;
        let guard = built(2, Duration::from_secs(5));

        assert_eq!(guard.technology(), "retry");
        assert_eq!(
            guard.after(&failed(1)),
            Decision::Wait(Duration::from_secs(5))
        );
        assert_eq!(guard.after(&failed(2)), Decision::Proceed, "its last try");
    }

    #[test]
    fn every_build_verifies_a_drop_folders_implied_identity() {
        let mechanisms: Vec<String> = authenticators()
            .iter()
            .map(|authenticator| authenticator.mechanism().name().to_string())
            .collect();

        assert!(
            mechanisms.contains(&"circumstance".to_string()),
            "{mechanisms:?}"
        );
    }

    #[cfg(feature = "persist-rocksdb")]
    #[test]
    fn the_store_is_linked_where_the_build_carries_its_engine() {
        let engine = engine().map(|engine| engine.technology());
        let stores: Vec<&str> = key_stores()
            .iter()
            .map(LinkedKeyStore::technology)
            .collect();

        assert_eq!(engine, Some(xmip_configure::store::ENGINE));
        assert!(
            stores.contains(&xmip_configure::store::PLATFORM_KEY_STORE),
            "{stores:?}"
        );
    }
}
