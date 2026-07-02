use crate::actor_model::{ActorCapability, ActorKind};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ArtifactCapabilities {
    pub artifact: ActorKind,
    pub can_transform: bool,
    pub can_assign: bool,
}

pub const RECEIVE_PORT_CAPABILITIES: ArtifactCapabilities = ArtifactCapabilities {
    artifact: ActorKind::ReceivePort,
    can_transform: true,
    can_assign: false,
};

pub const PROCESS_CAPABILITIES: ArtifactCapabilities = ArtifactCapabilities {
    artifact: ActorKind::Process,
    can_transform: true,
    can_assign: true,
};

pub const SEND_PORT_CAPABILITIES: ArtifactCapabilities = ArtifactCapabilities {
    artifact: ActorKind::SendPort,
    can_transform: true,
    can_assign: false,
};

pub fn can_assign(kind: ActorKind) -> bool {
    matches!(kind, ActorKind::Process)
}

pub fn can_transform(kind: ActorKind) -> bool {
    matches!(kind, ActorKind::ReceivePort | ActorKind::Process | ActorKind::SendPort)
}

pub fn capability_allowed(kind: ActorKind, capability: ActorCapability) -> bool {
    match capability {
        ActorCapability::Transform => can_transform(kind),
        ActorCapability::Execute => matches!(kind, ActorKind::Process),
        _ => true,
    }
}
