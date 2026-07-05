use xmip_linear_kernel::protocol_catalog::{chain_to_root, depends_on, parent_of};

#[test]
fn mllp_and_hl7v2_follow_the_tcp_chain() {
    assert_eq!(parent_of("mllp"), Some("tcp"));
    assert_eq!(parent_of("hl7v2"), Some("mllp"));
    assert!(depends_on("hl7v2", "tcp"));
    assert_eq!(chain_to_root("hl7v2"), vec!["hl7v2", "mllp", "tcp"]);
}

#[test]
fn fhir_follows_the_http_chain() {
    assert_eq!(parent_of("http"), Some("tcp"));
    assert_eq!(parent_of("fhir"), Some("http"));
    assert!(depends_on("fhir", "tcp"));
    assert_eq!(chain_to_root("fhir"), vec!["fhir", "http", "tcp"]);
}

#[test]
fn nmea2000_follows_the_canbus_chain() {
    assert_eq!(parent_of("nmea2000"), Some("canbus"));
    assert!(depends_on("nmea2000", "canbus"));
    assert_eq!(chain_to_root("nmea2000"), vec!["nmea2000", "canbus"]);
}
