use xmip_linear_kernel::handler_universe::HandlerSpace;
use xmip_linear_kernel::handler_universe_registry::{
    all_handler_repositories, find_handler_repository, repositories_for_space,
    validate_handler_universe,
};

#[test]
fn handler_universe_is_valid() {
    validate_handler_universe().expect("handler universe should be valid");
}

#[test]
fn handler_universe_contains_core_required_handlers() {
    for repository_name in [
        "xmip-handler-file",
        "xmip-handler-ftp",
        "xmip-handler-http",
        "xmip-handler-web-api",
        "xmip-handler-soap",
        "xmip-handler-websocket",
        "xmip-handler-grpc",
        "xmip-handler-mllp",
        "xmip-handler-rabbitmq",
        "xmip-handler-kafka",
        "xmip-handler-canbus",
        "xmip-handler-nmea2000",
        "xmip-handler-opc-ua",
        "xmip-handler-hl7",
        "xmip-handler-fhir",
        "xmip-handler-swift",
        "xmip-handler-sap",
    ] {
        assert!(
            find_handler_repository(repository_name).is_some(),
            "missing handler repository: {}",
            repository_name
        );
    }
}

#[test]
fn every_declared_space_has_handlers() {
    for space in [
        HandlerSpace::FileTransfer,
        HandlerSpace::NetworkWeb,
        HandlerSpace::MessagingStreaming,
        HandlerSpace::Healthcare,
        HandlerSpace::IndustrialIoT,
        HandlerSpace::EnergyUtilities,
        HandlerSpace::FinancePayments,
        HandlerSpace::BusinessDocuments,
        HandlerSpace::DatabaseStorage,
        HandlerSpace::EmailCollaboration,
        HandlerSpace::EnterpriseSaaS,
        HandlerSpace::IdentityDirectory,
        HandlerSpace::GovernmentExchange,
        HandlerSpace::Geospatial,
    ] {
        assert!(
            !repositories_for_space(space).is_empty(),
            "handler space has no repositories: {:?}",
            space
        );
    }
}

#[test]
fn no_invalid_legacy_repositories_are_declared() {
    let names: Vec<&str> = all_handler_repositories()
        .into_iter()
        .map(|repository| repository.repository_name)
        .collect();

    assert!(!names.contains(&"xmip-handler-fil"));
    assert!(!names.contains(&"xmip-handler-udp-bas"));
    assert!(!names.contains(&"mip-handler-canbus"));
}
