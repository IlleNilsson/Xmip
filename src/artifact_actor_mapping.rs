use crate::actor_model::{ActorKind, ActorRef, ActorRole};

pub fn receive_location_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::ReceiveLocation,
        name,
        vec![ActorRole::Receiver, ActorRole::Publisher, ActorRole::Reporter],
    )
}

pub fn receive_port_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::ReceivePort,
        name,
        vec![ActorRole::Subscriber, ActorRole::Owner, ActorRole::Publisher],
    )
}

pub fn process_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::Process,
        name,
        vec![
            ActorRole::Subscriber,
            ActorRole::Owner,
            ActorRole::Publisher,
            ActorRole::Executor,
            ActorRole::Transformer,
            ActorRole::Router,
        ],
    )
}

pub fn send_port_group_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::SendPortGroup,
        name,
        vec![ActorRole::Subscriber, ActorRole::Publisher],
    )
}

pub fn send_port_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::SendPort,
        name,
        vec![ActorRole::Subscriber, ActorRole::Owner, ActorRole::Sender],
    )
}

pub fn send_location_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::SendLocation,
        name,
        vec![ActorRole::Sender, ActorRole::Reporter],
    )
}
