use xmip_linear_kernel::actor_model::{ActorCapability, ActorKind};
use xmip_linear_kernel::artifact_capability_matrix::{
    can_assign, can_transform, capability_allowed, PROCESS_CAPABILITIES,
    RECEIVE_PORT_CAPABILITIES, SEND_PORT_CAPABILITIES,
};

#[test]
fn only_process_can_assign() {
    assert!(!can_assign(ActorKind::ReceivePort));
    assert!(can_assign(ActorKind::Process));
    assert!(!can_assign(ActorKind::SendPort));
}

#[test]
fn receive_process_and_send_ports_can_transform() {
    assert!(can_transform(ActorKind::ReceivePort));
    assert!(can_transform(ActorKind::Process));
    assert!(can_transform(ActorKind::SendPort));
    assert!(!can_transform(ActorKind::ReceiveLocation));
    assert!(!can_transform(ActorKind::SendLocation));
}

#[test]
fn capability_constants_reflect_agreed_architecture() {
    assert_eq!(RECEIVE_PORT_CAPABILITIES.artifact, ActorKind::ReceivePort);
    assert!(RECEIVE_PORT_CAPABILITIES.can_transform);
    assert!(!RECEIVE_PORT_CAPABILITIES.can_assign);

    assert_eq!(PROCESS_CAPABILITIES.artifact, ActorKind::Process);
    assert!(PROCESS_CAPABILITIES.can_transform);
    assert!(PROCESS_CAPABILITIES.can_assign);

    assert_eq!(SEND_PORT_CAPABILITIES.artifact, ActorKind::SendPort);
    assert!(SEND_PORT_CAPABILITIES.can_transform);
    assert!(!SEND_PORT_CAPABILITIES.can_assign);
}

#[test]
fn transform_capability_is_restricted_to_valid_artifacts() {
    assert!(capability_allowed(ActorKind::ReceivePort, ActorCapability::Transform));
    assert!(capability_allowed(ActorKind::Process, ActorCapability::Transform));
    assert!(capability_allowed(ActorKind::SendPort, ActorCapability::Transform));
    assert!(!capability_allowed(ActorKind::SendLocation, ActorCapability::Transform));
}
