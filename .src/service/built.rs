//! The technologies this build of `xmip-service` linked, handed to the node
//! it starts (`xmip_runtime::linked::Linked`). The build profile decides
//! which: each is a feature of this crate, and the node takes only what its
//! configuration names; a Location naming one this build left out is refused
//! as the node starts.
//!
//! Transports, and the runtime store's engines and key stores: the node
//! opens the store its `[store]` names, and one naming an engine or a key
//! store this build left out is refused as it starts (ADR-0018, amendment
//! 2026-09-30). No authenticator, policy, identifier or route technology is
//! linked, because the node configuration cannot yet say how one is set
//! up: a Receive Location that accepts nothing is refused nothing at the
//! start and takes no Stream through its gates.

use xmip_audit::program_audit::ProgramAudit;
use xmip_runtime::linked::{Linked, LinkedEngine, LinkedKeyStore, LinkedTransport};

/// What this build carries, and the audit an operator's act on a
/// Subscription is recorded in.
pub fn linked(audit: &ProgramAudit) -> Linked {
    Linked {
        transports: transports(),
        engines: engines(),
        key_stores: key_stores(),
        audit: Some(audit.clone()),
        ..Linked::default()
    }
}

/// The runtime store engines this build carries, each by its module name.
#[allow(
    unused_mut,
    clippy::vec_init_then_push,
    reason = "each push is a feature this build may leave out"
)]
pub fn engines() -> Vec<LinkedEngine> {
    let mut engines = Vec::new();
    #[cfg(feature = "persist-rocksdb")]
    engines.push(LinkedEngine::new("xmip-core-persist-rocksdb", |place| {
        Ok(Box::new(xmip_persist_rocksdb::RocksDb::open(place)?))
    }));
    #[cfg(feature = "persist-sqlite")]
    engines.push(LinkedEngine::new("xmip-core-persist-sqlite", |place| {
        Ok(Box::new(xmip_persist_sqlite::Sqlite::open(place)?))
    }));
    engines
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

    #[cfg(feature = "persist-rocksdb")]
    #[test]
    fn the_default_store_is_linked_where_the_build_carries_its_engine() {
        let engines: Vec<&str> = engines().iter().map(LinkedEngine::technology).collect();
        let stores: Vec<&str> = key_stores()
            .iter()
            .map(LinkedKeyStore::technology)
            .collect();

        assert!(
            engines.contains(&xmip_configure::store::DEFAULT_ENGINE),
            "{engines:?}"
        );
        assert!(
            stores.contains(&xmip_configure::store::PLATFORM_KEY_STORE),
            "{stores:?}"
        );
    }
}
