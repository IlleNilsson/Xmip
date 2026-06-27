use crate::actor_model::{ActorCapability, ActorKind, ActorRef};

pub fn receive_location_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::ReceiveLocation,
        name,
        vec![
            ActorCapability::Receive,
            ActorCapability::Publish,
            ActorCapability::Report,
        ],
    )
}

pub fn receive_port_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::ReceivePort,
        name,
        vec![
            ActorCapability::Subscribe,
            ActorCapability::OwnMessage,
            ActorCapability::Publish,
        ],
    )
}

pub fn process_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::Process,
        name,
        vec![
            ActorCapability::Subscribe,
            ActorCapability::OwnMessage,
            ActorCapability::Publish,
            ActorCapability::Execute,
            ActorCapability::Transform,
            ActorCapability::Route,
        ],
    )
}

pub fn send_port_group_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::SendPortGroup,
        name,
        vec![ActorCapability::Subscribe, ActorCapability::Publish],
    )
}

pub fn send_port_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::SendPort,
        name,
        vec![
            ActorCapability::Subscribe,
            ActorCapability::OwnMessage,
            ActorCapability::Send,
        ],
    )
}

pub fn send_location_actor(name: impl Into<String>) -> ActorRef {
    ActorRef::new(
        ActorKind::SendLocation,
        name,
        vec![ActorCapability::Send, ActorCapability::Report],
    )
}
