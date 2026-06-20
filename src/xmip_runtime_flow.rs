use crate::xmip_message_model::{
    AuditAction, AuditEntry, CreationInstance, CreationKind, Interchange, Message,
    PromotedProperty, Section,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeEnvelope {
    pub interchange: Interchange,
    pub current_message_id: uuid::Uuid,
    pub subscriptions: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiveCommand {
    pub cluster_name: String,
    pub node_name: String,
    pub receive_port: String,
    pub receive_location: String,
    pub sender_identity: String,
    pub content_type: String,
    pub stream_reference: String,
}

pub fn receive_stream(command: ReceiveCommand) -> Result<RuntimeEnvelope, String> {
    if command.sender_identity.trim().is_empty() {
        return Err("sender identity is required".to_string());
    }

    let receive_creation = CreationInstance::new(
        CreationKind::Receive,
        command.receive_port.clone(),
        command.cluster_name.clone(),
        command.node_name.clone(),
    );

    let section = Section::new(
        receive_creation.clone(),
        command.content_type,
        command.stream_reference,
    );

    let message = Message::receive(receive_creation, vec![section]);
    let message_id = message.message_id;
    let interchange_id = message.interchange_id;
    let mut interchange = Interchange::start(message);

    interchange.add_audit(AuditEntry::new(
        interchange_id,
        Some(message_id),
        AuditAction::Receive,
        command.receive_location,
        "received",
    ))?;

    interchange.add_audit(AuditEntry::new(
        interchange_id,
        Some(message_id),
        AuditAction::IdentityLookup,
        command.sender_identity,
        "identified",
    ))?;

    Ok(RuntimeEnvelope { interchange, current_message_id: message_id, subscriptions: Vec::new() })
}

pub fn authorize(mut envelope: RuntimeEnvelope, actor: impl Into<String>, allowed: bool) -> Result<RuntimeEnvelope, String> {
    let actor = actor.into();
    let message = envelope
        .interchange
        .messages
        .get(&envelope.current_message_id)
        .ok_or_else(|| "current message not found".to_string())?;

    let outcome = if allowed { "authorized" } else { "denied" };
    envelope.interchange.add_audit(AuditEntry::new(
        envelope.interchange.interchange_id,
        Some(message.message_id),
        AuditAction::Authorization,
        actor,
        outcome,
    ))?;

    if !allowed {
        return Err("sender is not authorized".to_string());
    }

    Ok(envelope)
}

pub fn promote(mut envelope: RuntimeEnvelope, properties: Vec<PromotedProperty>) -> Result<RuntimeEnvelope, String> {
    let current = envelope
        .interchange
        .messages
        .get(&envelope.current_message_id)
        .ok_or_else(|| "current message not found".to_string())?
        .clone();

    let assigned = current.assign(
        CreationInstance::new(CreationKind::Assignment, "promotion", "cluster", "node"),
        properties,
    );

    let new_id = assigned.message_id;
    envelope.interchange.add_message(assigned)?;
    envelope.interchange.add_audit(AuditEntry::new(
        envelope.interchange.interchange_id,
        Some(new_id),
        AuditAction::Promotion,
        "promotion-engine",
        "promoted",
    ))?;
    envelope.current_message_id = new_id;

    Ok(envelope)
}

pub fn transform(mut envelope: RuntimeEnvelope, content_type: impl Into<String>, stream_reference: impl Into<String>) -> Result<RuntimeEnvelope, String> {
    let current = envelope
        .interchange
        .messages
        .get(&envelope.current_message_id)
        .ok_or_else(|| "current message not found".to_string())?
        .clone();

    let creation = CreationInstance::new(CreationKind::Transformation, "transform", "cluster", "node");
    let section = Section::new(creation.clone(), content_type, stream_reference);
    let transformed = current.transform(creation, vec![section]);
    let new_id = transformed.message_id;

    envelope.interchange.add_message(transformed)?;
    envelope.interchange.add_audit(AuditEntry::new(
        envelope.interchange.interchange_id,
        Some(new_id),
        AuditAction::Transformation,
        "transformation-engine",
        "transformed",
    ))?;
    envelope.current_message_id = new_id;

    Ok(envelope)
}

pub fn subscribe(mut envelope: RuntimeEnvelope) -> Result<RuntimeEnvelope, String> {
    let current = envelope
        .interchange
        .messages
        .get(&envelope.current_message_id)
        .ok_or_else(|| "current message not found".to_string())?;

    envelope.subscriptions = current
        .promoted_properties
        .iter()
        .filter_map(|property| match (property.name.as_str(), property.value.as_str()) {
            ("message.type", "order") => Some("process:order-orchestration".to_string()),
            ("priority", "high") => Some("process:priority-monitoring".to_string()),
            ("destination", value) => Some(format!("sendPort:{value}")),
            _ => None,
        })
        .collect();

    envelope.interchange.add_audit(AuditEntry::new(
        envelope.interchange.interchange_id,
        Some(envelope.current_message_id),
        AuditAction::Subscription,
        "subscription-engine",
        format!("matched={}", envelope.subscriptions.len()),
    ))?;

    Ok(envelope)
}
