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
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActorRef {
    pub id: ActorId,
    pub kind: ActorKind,
    pub name: String,
    pub capabilities: Vec<ActorCapability>,
}

impl ActorRef {
    pub fn new(
        kind: ActorKind,
        name: impl Into<String>,
        capabilities: Vec<ActorCapability>,
    ) -> Self {
        Self {
            id: ActorId::new(),
            kind,
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
}
