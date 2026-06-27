use xmip_linear_kernel::actor_model::{ActorCapability, ActorKind, ActorMode, CompletionPolicy};
use xmip_linear_kernel::artifact_actor_mapping::process_actor;
use xmip_linear_kernel::sending_actor_mapping::{
    send_location_actor_with_completion, send_port_actor_with_completion,
};

#[test]
fn internal_executing_actor_is_not_a_sending_actor() {
    let actor = process_actor("process:transform-order");

    assert_eq!(actor.kind, ActorKind::Process);
    assert_eq!(actor.mode, ActorMode::Coordinating);
    assert!(!actor.is_sending());
    assert!(actor.capabilities.contains(&ActorCapability::Execute));
}

#[test]
fn sending_actor_is_distinct_from_executing_actor() {
    let actor = send_port_actor_with_completion("sendPort:orders", CompletionPolicy::NoError);

    assert_eq!(actor.kind, ActorKind::SendPort);
    assert!(actor.is_sending());
    assert!(!actor.is_executing());
    assert!(actor.expects_completion_result());
    assert_eq!(actor.completion_policy, Some(CompletionPolicy::NoError));
}

#[test]
fn sending_actor_can_use_exit_code_zero_completion() {
    let actor = send_location_actor_with_completion(
        "sendLocation:script",
        CompletionPolicy::ExitCodeZero,
    );

    assert!(actor.is_sending());
    assert_eq!(actor.completion_policy, Some(CompletionPolicy::ExitCodeZero));
}

#[test]
fn sending_actor_can_require_response_completion() {
    let actor = send_location_actor_with_completion(
        "sendLocation:http-api",
        CompletionPolicy::Response,
    );

    assert!(actor.is_sending());
    assert_eq!(actor.completion_policy, Some(CompletionPolicy::Response));
}
