use xmip_linear_kernel::actor_model::{ActorKind, ActorRole};
use xmip_linear_kernel::artifact_actor_mapping::{
    process_actor, receive_location_actor, receive_port_actor, send_location_actor,
    send_port_actor, send_port_group_actor,
};

#[test]
fn receive_location_reports_and_publishes_to_receive_port() {
    let actor = receive_location_actor("receiveLocation:file-in");

    assert_eq!(actor.kind, ActorKind::ReceiveLocation);
    assert!(actor.roles.contains(&ActorRole::Receiver));
    assert!(actor.roles.contains(&ActorRole::Reporter));
    assert!(actor.can_publish());
}

#[test]
fn receive_port_can_own_and_publish_message() {
    let actor = receive_port_actor("receivePort:orders");

    assert_eq!(actor.kind, ActorKind::ReceivePort);
    assert!(actor.can_own());
    assert!(actor.can_publish());
    assert!(actor.can_subscribe());
}

#[test]
fn process_can_own_transform_route_publish_and_subscribe() {
    let actor = process_actor("process:order-flow");

    assert_eq!(actor.kind, ActorKind::Process);
    assert!(actor.can_own());
    assert!(actor.can_publish());
    assert!(actor.can_subscribe());
    assert!(actor.roles.contains(&ActorRole::Transformer));
    assert!(actor.roles.contains(&ActorRole::Router));
    assert!(actor.roles.contains(&ActorRole::Executor));
}

#[test]
fn send_side_artifacts_have_distinct_actor_roles() {
    let group = send_port_group_actor("sendPortGroup:orders");
    let port = send_port_actor("sendPort:orders-out");
    let location = send_location_actor("sendLocation:https-out");

    assert_eq!(group.kind, ActorKind::SendPortGroup);
    assert_eq!(port.kind, ActorKind::SendPort);
    assert_eq!(location.kind, ActorKind::SendLocation);

    assert!(group.can_publish());
    assert!(port.can_own());
    assert!(location.roles.contains(&ActorRole::Sender));
    assert!(location.roles.contains(&ActorRole::Reporter));
}
