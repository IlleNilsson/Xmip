#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EnablerKind {
    ReceivePort,
    ReceiveLocation,
    Subscription,
    Process,
    SendPort,
    SendLocation,
    Contract,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnablerDefinition {
    pub name: String,
    pub kind: EnablerKind,
    pub handler_reference: Option<String>,
    pub handler_configuration: Option<String>,
    pub runtime_configuration: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EnablerInstanceOutcome {
    Running,
    Succeeded,
    SucceededWithWarnings,
    Failed,
    Rejected,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnablerInstance {
    pub instance_id: String,
    pub definition_name: String,
    pub kind: EnablerKind,
    pub message_id: String,
    pub outcome: EnablerInstanceOutcome,
}

impl EnablerInstance {
    pub fn from_definition(
        instance_id: String,
        definition: &EnablerDefinition,
        message_id: String,
    ) -> Self {
        Self {
            instance_id,
            definition_name: definition.name.clone(),
            kind: definition.kind.clone(),
            message_id,
            outcome: EnablerInstanceOutcome::Running,
        }
    }
}
