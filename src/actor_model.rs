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
pub enum ActorRole {
    Publisher,
    Subscriber,
    Owner,
    Reporter,
    Commander,
    Executor,
    Router,
    Transformer,
    Sender,
    Receiver,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActorRef {
    pub id: ActorId,
    pub kind: ActorKind,
    pub name: String,
    pub roles: Vec<ActorRole>,
}

impl ActorRef {
    pub fn new(kind: ActorKind, name: impl Into<String>, roles: Vec<ActorRole>) -> Self {
        Self {
            id: ActorId::new(),
            kind,
            name: name.into(),
            roles,
        }
    }

    pub fn can_publish(&self) -> bool {
        self.roles.contains(&ActorRole::Publisher)
    }

    pub fn can_subscribe(&self) -> bool {
        self.roles.contains(&ActorRole::Subscriber)
    }

    pub fn can_own(&self) -> bool {
        self.roles.contains(&ActorRole::Owner)
    }
}
