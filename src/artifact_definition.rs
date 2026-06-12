#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ArtifactKind {
    ReceivePort,
    ReceiveLocation,
    Subscription,
    BusinessProcess,
    SendPort,
    SendLocation,
    Contract,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArtifactDefinition {
    pub name: String,
    pub kind: ArtifactKind,
    pub handler_reference: String,
    pub handler_configuration: String,
    pub runtime_configuration: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ArtifactInstanceOutcome {
    Running,
    Succeeded,
    Failed,
    Rejected,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArtifactInstance {
    pub instance_id: String,
    pub definition_name: String,
    pub kind: ArtifactKind,
    pub message_id: String,
    pub outcome: ArtifactInstanceOutcome,
}

impl ArtifactInstance {
    pub fn from_definition(
        instance_id: String,
        definition: &ArtifactDefinition,
        message_id: String,
    ) -> Self {
        Self {
            instance_id,
            definition_name: definition.name.clone(),
            kind: definition.kind.clone(),
            message_id,
            outcome: ArtifactInstanceOutcome::Running,
        }
    }
}
