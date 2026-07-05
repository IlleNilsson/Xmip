use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreationInstance {
    pub when_utc: String,
    pub by: CreationActor,
    pub name: String,
    pub cluster_name: String,
    pub node_name: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum CreationActor {
    Port,
    Assignment,
    Transformation,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ActionType {
    Receive,
    Process,
    Assignment,
    Send,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActionContext {
    pub action_type: ActionType,
    pub receive_port_name: Option<String>,
    pub receive_location_name: Option<String>,
    pub process_name: Option<String>,
    pub assignment_name: Option<String>,
    pub send_port_name: Option<String>,
    pub send_location_name: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct XmipMessage {
    pub interchange_id: Uuid,
    pub message_id: Uuid,
    pub creation_instance: CreationInstance,
    pub action_context: ActionContext,
    pub sections: Vec<MessageSection>,
    pub promoted_properties: Vec<PromotedProperty>,
    pub lineage: Vec<MessageLineageEntry>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageSection {
    pub section_id: Uuid,
    pub creation_instance: CreationInstance,
    pub stream_ref: StreamRef,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StreamRef {
    pub uri: String,
    pub content_type: Option<String>,
    pub unchanged_from_section_id: Option<Uuid>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PromotedProperty {
    pub name: String,
    pub value: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageLineageEntry {
    pub previous_message_id: Option<Uuid>,
    pub operation: LineageOperation,
    pub operation_name: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum LineageOperation {
    Receive,
    Assignment,
    Transformation,
    Process,
    Send,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ArtifactIdentity {
    pub cluster_name: String,
    pub artifact_name: String,
    pub version: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReceivePort {
    pub identity: ArtifactIdentity,
    pub priority: Priority,
    pub locations: Vec<ReceiveLocation>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReceiveLocation {
    pub name: String,
    pub version: String,
    pub transport_handler: String,
    pub content_handler: Option<String>,
    pub contract: Option<ContractRef>,
    pub auth: AuthPolicy,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SendPort {
    pub identity: ArtifactIdentity,
    pub priority: Priority,
    pub locations: Vec<SendLocation>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SendLocation {
    pub name: String,
    pub version: String,
    pub transport_handler: String,
    pub retry: RetryPolicy,
    pub auth: AuthPolicy,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProcessArtifact {
    pub identity: ArtifactIdentity,
    pub priority: Priority,
    pub execution_style: ExecutionStyle,
    pub receive_port_name: String,
    pub send_port_name: Option<String>,
    pub assignments: Vec<String>,
    pub transformations: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Priority {
    Low,
    Normal,
    High,
    Critical,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ExecutionStyle {
    Sequential,
    Parallel,
    Concurrent,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContractRef {
    pub kind: ContractKind,
    pub uri: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ContractKind {
    XmlSchema,
    JsonSchema,
    Regex,
    Any,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AuthPolicy {
    pub required: bool,
    pub pass_through_identity: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RetryPolicy {
    pub retries_per_location: u32,
    pub failover_on_non_retryable_error: bool,
}

pub fn transformed_message(
    source: &XmipMessage,
    creation_instance: CreationInstance,
    operation_name: impl Into<String>,
    sections: Vec<MessageSection>,
) -> XmipMessage {
    XmipMessage {
        interchange_id: source.interchange_id,
        message_id: Uuid::new_v4(),
        creation_instance,
        action_context: ActionContext {
            action_type: ActionType::Assignment,
            receive_port_name: None,
            receive_location_name: None,
            process_name: source.action_context.process_name.clone(),
            assignment_name: None,
            send_port_name: None,
            send_location_name: None,
        },
        sections,
        promoted_properties: source.promoted_properties.clone(),
        lineage: {
            let mut lineage = source.lineage.clone();
            lineage.push(MessageLineageEntry {
                previous_message_id: Some(source.message_id),
                operation: LineageOperation::Transformation,
                operation_name: operation_name.into(),
            });
            lineage
        },
    }
}

pub fn validate_action_context(context: &ActionContext) -> Result<(), String> {
    match context.action_type {
        ActionType::Receive => require_pair(
            "receive",
            context.receive_port_name.as_ref(),
            "receive_port_name",
            context.receive_location_name.as_ref(),
            "receive_location_name",
        ),
        ActionType::Process => require_one("process", context.process_name.as_ref(), "process_name"),
        ActionType::Assignment => {
            require_one("assignment", context.process_name.as_ref(), "process_name")?;
            require_one("assignment", context.assignment_name.as_ref(), "assignment_name")
        }
        ActionType::Send => require_pair(
            "send",
            context.send_port_name.as_ref(),
            "send_port_name",
            context.send_location_name.as_ref(),
            "send_location_name",
        ),
    }
}

fn require_one(action: &str, value: Option<&String>, field: &str) -> Result<(), String> {
    if value.map(|v| !v.is_empty()).unwrap_or(false) {
        Ok(())
    } else {
        Err(format!("{action} action requires {field}"))
    }
}

fn require_pair(
    action: &str,
    first_value: Option<&String>,
    first_field: &str,
    second_value: Option<&String>,
    second_field: &str,
) -> Result<(), String> {
    require_one(action, first_value, first_field)?;
    require_one(action, second_value, second_field)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn receive_action_requires_port_and_location() {
        let context = ActionContext {
            action_type: ActionType::Receive,
            receive_port_name: Some("orders".to_string()),
            receive_location_name: None,
            process_name: None,
            assignment_name: None,
            send_port_name: None,
            send_location_name: None,
        };

        assert!(validate_action_context(&context).is_err());
    }

    #[test]
    fn send_action_accepts_port_and_location() {
        let context = ActionContext {
            action_type: ActionType::Send,
            receive_port_name: None,
            receive_location_name: None,
            process_name: None,
            assignment_name: None,
            send_port_name: Some("orders-out".to_string()),
            send_location_name: Some("archive".to_string()),
        };

        assert!(validate_action_context(&context).is_ok());
    }
}
