//! The cluster's certificate authority a Storage test makes, and the
//! identities it issues: what the Storage tests (`served.rs`) and the
//! root's timing program (`.src/test/measured/wire.rs`) both reach a
//! Storage node over mutual TLS with. Shared, not copied.

use std::path::Path;

/// The authority's certificate, the same every time it is made from the
/// same key: what a leaf names as its issuer and what an anchor holds.
fn authority_params() -> rcgen::CertificateParams {
    let mut params = rcgen::CertificateParams::new(Vec::<String>::new()).expect("params");
    params.is_ca = rcgen::IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
    params
}

/// The cluster's certificate authority in a test's directory, made once
/// by the test before any child starts: its certificate and its key, PEM.
pub fn authority(place: &Path) {
    let key = rcgen::KeyPair::generate().expect("a key");
    let cert = authority_params().self_signed(&key).expect("signed");
    std::fs::write(place.join("authority.pem"), cert.pem()).expect("written");
    std::fs::write(place.join("authority-key.pem"), key.serialize_pem()).expect("written");
}

/// An identity the authority in `place` issues to a node at 127.0.0.1.
pub fn issue(place: &Path) -> xmip_tls::Identity {
    let authority_pem = std::fs::read_to_string(place.join("authority.pem")).expect("read");
    let authority_key = std::fs::read_to_string(place.join("authority-key.pem")).expect("read");
    let authority_key = rcgen::KeyPair::from_pem(&authority_key).expect("the authority's key");
    let issuer = rcgen::Issuer::new(authority_params(), authority_key);
    let key = rcgen::KeyPair::generate().expect("a key");
    let mut params = rcgen::CertificateParams::new(vec!["127.0.0.1".to_string()]).expect("params");
    // Server and client authentication, as a node's certificate is (ADR-0034):
    // what the Storage plane admits.
    params.extended_key_usages = vec![
        rcgen::ExtendedKeyUsagePurpose::ServerAuth,
        rcgen::ExtendedKeyUsagePurpose::ClientAuth,
    ];
    let leaf = params.signed_by(&key, &issuer).expect("issued");
    xmip_tls::Identity::from_pem(
        leaf.pem().as_bytes(),
        key.serialize_pem().as_bytes(),
        authority_pem.as_bytes(),
    )
    .expect("an identity")
}
