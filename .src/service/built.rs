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
//! audited with the claim it carried (ADR-0013 clause 1). No route
//! technology is linked yet.

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
        engine: engine(),
        administration: administration(),
        key_stores: key_stores(),
        #[cfg(feature = "identify")]
        transport_identifiers: transport_identifiers(),
        authenticators: authenticators(),
        location_policies: location_policies(),
        audit: Some(audit.clone()),
        ..Linked::default()
    }
}

/// The authenticators this build carries, each taken where a Receive
/// Location the node starts accepts its mechanism: `circumstance` in every
/// build, since every node infers a circumstance where nothing was
/// presented (ADR-0019 clause 7), and those the site linked.
#[allow(
    unused_mut,
    clippy::vec_init_then_push,
    reason = "each push after the first is a feature this build may leave out"
)]
pub fn authenticators() -> Vec<Box<dyn Authenticator>> {
    let mut authenticators: Vec<Box<dyn Authenticator>> = Vec::new();
    authenticators.push(Box::new(xmip_authenticate::Circumstance));
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

/// The runtime database's engine, where this build carries it.
#[allow(
    clippy::unnecessary_wraps,
    reason = "a build without persist-rocksdb carries no engine"
)]
pub fn engine() -> Option<LinkedEngine> {
    #[cfg(feature = "persist-rocksdb")]
    return Some(LinkedEngine::new(xmip_configure::store::ENGINE, |place| {
        Ok(Box::new(xmip_persist_rocksdb::RocksDb::open(place)?))
    }));
    #[cfg(not(feature = "persist-rocksdb"))]
    None
}

/// The administration database's engine, where this build carries it.
#[allow(
    clippy::unnecessary_wraps,
    reason = "a build without persist-sqlite carries no administration database"
)]
pub fn administration() -> Option<LinkedEngine> {
    #[cfg(feature = "persist-sqlite")]
    return Some(LinkedEngine::new(
        xmip_runtime::storage::ADMINISTRATION,
        |place| Ok(Box::new(xmip_persist_sqlite::Sqlite::open(place)?)),
    ));
    #[cfg(not(feature = "persist-sqlite"))]
    None
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
/// verified before a credential sent inside the connection.
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
    #[cfg(feature = "identify-ip")]
    identifiers.push(Box::new(xmip_identify_ip::IpIdentifier::new()));
    identifiers
}

/// The transports this build carries, each by its own declaration.
#[allow(
    unused_mut,
    clippy::vec_init_then_push,
    reason = "each push is a feature this build may leave out"
)]
pub fn transports() -> Vec<LinkedTransport> {
    let mut transports = Vec::new();
    #[cfg(feature = "transport-file")]
    transports.push(LinkedTransport::of::<xmip_transport_file::FileTransport>());
    #[cfg(feature = "transport-http")]
    transports.push(LinkedTransport::of::<xmip_transport_http::HttpTransport>());
    #[cfg(feature = "transport-tcp")]
    transports.push(LinkedTransport::of::<xmip_transport_tcp::TcpTransport>());
    #[cfg(feature = "transport-udp")]
    transports.push(LinkedTransport::of::<xmip_transport_udp::UdpTransport>());
    transports
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_transport_is_linked_by_the_name_a_location_gives_it() {
        let names: Vec<&str> = transports()
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
             [[send_locations]]\nname = \"Out\"\ntransport = \"t\"\naddress = \"a\"\n",
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
                .decide(&facts, &Attempt::new(Action::Receive, "In"))
                .is_some_and(|decision| decision.allowed())
        );
        assert_eq!(
            policy.decide(&facts, &Attempt::new(Action::Receive, "Elsewhere")),
            None
        );
        assert!(
            policy
                .decide(&facts, &Attempt::new(Action::Send, "Out"))
                .is_some_and(|decision| decision.allowed()),
            "the owner, 2026-10-19: a Send Location the node starts is admitted"
        );
        assert_eq!(
            policy.decide(&facts, &Attempt::new(Action::Send, "Elsewhere")),
            None
        );
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
