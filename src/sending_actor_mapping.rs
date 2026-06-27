use crate::actor_model::{ActorCapability, ActorKind, ActorRef, CompletionPolicy};

pub fn send_port_actor_with_completion(
    name: impl Into<String>,
    completion_policy: CompletionPolicy,
) -> ActorRef {
    ActorRef::sending(
        ActorKind::SendPort,
        name,
        vec![
            ActorCapability::Subscribe,
            ActorCapability::OwnMessage,
            ActorCapability::Send,
        ],
        completion_policy,
    )
}

pub fn send_location_actor_with_completion(
    name: impl Into<String>,
    completion_policy: CompletionPolicy,
) -> ActorRef {
    ActorRef::sending(
        ActorKind::SendLocation,
        name,
        vec![ActorCapability::Send, ActorCapability::Report],
        completion_policy,
    )
}
