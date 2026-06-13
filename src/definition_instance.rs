#[derive(Debug, Clone, PartialEq, Eq)]
pub enum XmipDefinitionKind {
    ReceivePort,
    ReceiveLocation,
    Subscription,
    Process,
    SendPort,
    SendLocation,
    Contract,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmipDefinition {
    pub name: String,
    pub kind: XmipDefinitionKind,
    pub handler_reference: Option<String>,
    pub handler_configuration: Option<String>,
    pub runtime_configuration: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum XmipInstanceOutcome {
    Running,
    Succeeded,
    SucceededWithWarnings,
    Failed,
    Rejected,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmipInstance {
    pub instance_id: String,
    pub definition_name: String,
    pub kind: XmipDefinitionKind,
    pub message_id: String,
    pub outcome: XmipInstanceOutcome,
}

impl XmipInstance {
    pub fn from_definition(
        instance_id: String,
        definition: &XmipDefinition,
        message_id: String,
    ) -> Self {
        Self {
            instance_id,
            definition_name: definition.name.clone(),
            kind: definition.kind.clone(),
            message_id,
            outcome: XmipInstanceOutcome::Running,
        }
    }
}
