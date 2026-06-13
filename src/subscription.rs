#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubscriptionDefinition {
    pub name: String,
    pub pattern: SubscriptionPattern,
    pub action: SubscriptionAction,
    pub priority: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubscriptionPattern {
    pub expression: String,
    pub uses_promoted_properties: bool,
    pub uses_message_metadata: bool,
    pub uses_interchange_history: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SubscriptionAction {
    KickOffProcess { process_definition: String },
    ResumeProcess { process_instance_id: String },
    KickOffSendPort { send_port: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SubscriptionOutcome {
    Matched,
    NotMatched,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubscriptionInstance {
    pub instance_id: String,
    pub definition_name: String,
    pub message_id: String,
    pub interchange_chain: Vec<String>,
    pub outcome: SubscriptionOutcome,
    pub created_action: Option<SubscriptionAction>,
}

impl SubscriptionInstance {
    pub fn matched(
        instance_id: String,
        definition: &SubscriptionDefinition,
        message_id: String,
        interchange_chain: Vec<String>,
    ) -> Self {
        Self {
            instance_id,
            definition_name: definition.name.clone(),
            message_id,
            interchange_chain,
            outcome: SubscriptionOutcome::Matched,
            created_action: Some(definition.action.clone()),
        }
    }

    pub fn not_matched(
        instance_id: String,
        definition: &SubscriptionDefinition,
        message_id: String,
        interchange_chain: Vec<String>,
    ) -> Self {
        Self {
            instance_id,
            definition_name: definition.name.clone(),
            message_id,
            interchange_chain,
            outcome: SubscriptionOutcome::NotMatched,
            created_action: None,
        }
    }
}
