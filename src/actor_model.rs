use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ActorId(pub Uuid);

impl ActorId {
    pub fn new() -> Self {
        Self(Uuid::new_v4())
    }
}

impl Default for ActorId {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ActorKind {
    Organization,
    Domain,
    Cluster,
    Node,
    HostProcess,
    Handler,
    ReceivePort,
    ReceiveLocation,
    Process,
    SendPortGroup,
    SendPort,
    SendLocation,
    ExternalSystem,
    Person,
    Device,
    Sensor,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ActorMode {
    Observing,
    Executing,
    Coordinating,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ActorCapability {
    Publish,
    Subscribe,
    OwnMessage,
    Report,
    Command,
    Execute,
    Route,
    Transform,
    Send,
    Receive,
    Observe,
    RequireResponse,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActorRef {
    pub id: ActorId,
    pub kind: ActorKind,
    pub mode: ActorMode,
    pub name: String,
    pub capabilities: Vec<ActorCapability>,
}

impl ActorRef {
    pub fn new(
        kind: ActorKind,
        name: impl Into<String>,
        capabilities: Vec<ActorCapability>,
    ) -> Self {
        Self::new_with_mode(ActorMode::Coordinating, kind, name, capabilities)
    }

    pub fn observing(
        kind: ActorKind,
        name: impl Into<String>,
        capabilities: Vec<ActorCapability>,
    ) -> Self {
        Self::new_with_mode(ActorMode::Observing, kind, name, capabilities)
    }

    pub fn executing(
        kind: ActorKind,
        name: impl Into<String>,
        capabilities: Vec<ActorCapability>,
    ) -> Self {
        Self::new_with_mode(ActorMode::Executing, kind, name, capabilities)
    }

    pub fn coordinating(
        kind: ActorKind,
        name: impl Into<String>,
        capabilities: Vec<ActorCapability>,
    ) -> Self {
        Self::new_with_mode(ActorMode::Coordinating, kind, name, capabilities)
    }

    fn new_with_mode(
        mode: ActorMode,
        kind: ActorKind,
        name: impl Into<String>,
        capabilities: Vec<ActorCapability>,
    ) -> Self {
        Self {
            id: ActorId::new(),
            kind,
            mode,
            name: name.into(),
            capabilities,
        }
    }

    pub fn can_publish(&self) -> bool {
        self.capabilities.contains(&ActorCapability::Publish)
    }

    pub fn can_subscribe(&self) -> bool {
        self.capabilities.contains(&ActorCapability::Subscribe)
    }

    pub fn can_own_message(&self) -> bool {
        self.capabilities.contains(&ActorCapability::OwnMessage)
    }

    pub fn is_observing(&self) -> bool {
        self.mode == ActorMode::Observing
    }

    pub fn is_executing(&self) -> bool {
        self.mode == ActorMode::Executing
    }

    pub fn requires_response(&self) -> bool {
        self.capabilities.contains(&ActorCapability::RequireResponse)
    }
}
