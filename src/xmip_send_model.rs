use crate::xmip_message_model::{AuditAction, AuditEntry, CreationInstance, CreationKind, Interchange, Message, PromotedProperty, Section};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendLocationRole {
    Primary,
    Secondary,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendLocation {
    pub name: String,
    pub role: SendLocationRole,
    pub target_uri: String,
    pub retry_count: u32,
}

impl SendLocation {
    pub fn primary(name: impl Into<String>, target_uri: impl Into<String>, retry_count: u32) -> Self {
        Self { name: name.into(), role: SendLocationRole::Primary, target_uri: target_uri.into(), retry_count }
    }

    pub fn secondary(name: impl Into<String>, target_uri: impl Into<String>, retry_count: u32) -> Self {
        Self { name: name.into(), role: SendLocationRole::Secondary, target_uri: target_uri.into(), retry_count }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPort {
    pub name: String,
    pub locations: Vec<SendLocation>,
    pub send_side_promotions: Vec<PromotedProperty>,
    pub send_side_transform_content_type: Option<String>,
}

impl SendPort {
    pub fn new(name: impl Into<String>, locations: Vec<SendLocation>) -> Result<Self, String> {
        if locations.is_empty() {
            return Err("send port requires at least one send location".to_string());
        }

        Ok(Self {
            name: name.into(),
            locations,
            send_side_promotions: Vec::new(),
            send_side_transform_content_type: None,
        })
    }

    pub fn with_promotion(mut self, property: PromotedProperty) -> Self {
        self.send_side_promotions.push(property);
        self
    }

    pub fn with_transform(mut self, content_type: impl Into<String>) -> Self {
        self.send_side_transform_content_type = Some(content_type.into());
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendFailureKind {
    Retryable,
    NonRetryable,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendAttemptOutcome {
    Success,
    Failure { kind: SendFailureKind, reason: String },
}

pub trait SendTransport {
    fn send(&self, location: &SendLocation, message: &Message) -> SendAttemptOutcome;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendStatus {
    Success,
    SuccessWithWarnings,
    Failure,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendLocationResult {
    pub location_name: String,
    pub attempts: u32,
    pub outcome: SendAttemptOutcome,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendResult {
    pub send_port_name: String,
    pub status: SendStatus,
    pub successful_location: Option<String>,
    pub location_results: Vec<SendLocationResult>,
    pub warnings: Vec<String>,
    pub error: Option<String>,
}

pub struct SendRuntime;

impl SendRuntime {
    pub fn execute<T: SendTransport>(
        interchange: &mut Interchange,
        source_message_id: Uuid,
        send_port: &SendPort,
        transport: &T,
    ) -> Result<SendResult, String> {
        let mut working_message = interchange
            .messages
            .get(&source_message_id)
            .ok_or_else(|| "source message not found".to_string())?
            .clone();

        if !send_port.send_side_promotions.is_empty() {
            working_message = working_message.assign(
                CreationInstance::new(CreationKind::Assignment, format!("send-promotion:{}", send_port.name), "cluster", "node"),
                send_port.send_side_promotions.clone(),
            );
            interchange.add_message(working_message.clone())?;
            interchange.add_audit(AuditEntry::new(interchange.interchange_id, Some(working_message.message_id), AuditAction::Promotion, send_port.name.clone(), "send-side promotion"))?;
        }

        if let Some(content_type) = &send_port.send_side_transform_content_type {
            let creation = CreationInstance::new(CreationKind::Transformation, format!("send-transform:{}", send_port.name), "cluster", "node");
            let section = Section::new(creation.clone(), content_type.clone(), format!("send://{}/payload", send_port.name));
            working_message = working_message.transform(creation, vec![section]);
            interchange.add_message(working_message.clone())?;
            interchange.add_audit(AuditEntry::new(interchange.interchange_id, Some(working_message.message_id), AuditAction::Transformation, send_port.name.clone(), "send-side transform"))?;
        }

        let mut warnings = Vec::new();
        let mut location_results = Vec::new();

        for location in &send_port.locations {
            let mut attempt = 0;

            loop {
                attempt += 1;
                let outcome = transport.send(location, &working_message);

                match &outcome {
                    SendAttemptOutcome::Success => {
                        interchange.add_audit(AuditEntry::new(interchange.interchange_id, Some(working_message.message_id), AuditAction::Send, location.name.clone(), "success"))?;
                        location_results.push(SendLocationResult { location_name: location.name.clone(), attempts: attempt, outcome });

                        let status = if warnings.is_empty() { SendStatus::Success } else { SendStatus::SuccessWithWarnings };

                        return Ok(SendResult {
                            send_port_name: send_port.name.clone(),
                            status,
                            successful_location: Some(location.name.clone()),
                            location_results,
                            warnings,
                            error: None,
                        });
                    }
                    SendAttemptOutcome::Failure { kind: SendFailureKind::Retryable, reason } => {
                        if attempt <= location.retry_count {
                            continue;
                        }

                        let warning = format!("{} failed after retries: {}", location.name, reason);
                        warnings.push(warning.clone());
                        interchange.add_audit(AuditEntry::new(interchange.interchange_id, Some(working_message.message_id), AuditAction::Failure, location.name.clone(), warning))?;
                        location_results.push(SendLocationResult { location_name: location.name.clone(), attempts: attempt, outcome });
                        break;
                    }
                    SendAttemptOutcome::Failure { kind: SendFailureKind::NonRetryable, reason } => {
                        let warning = format!("{} non-retryable failure: {}", location.name, reason);
                        warnings.push(warning.clone());
                        interchange.add_audit(AuditEntry::new(interchange.interchange_id, Some(working_message.message_id), AuditAction::Failure, location.name.clone(), warning))?;
                        location_results.push(SendLocationResult { location_name: location.name.clone(), attempts: attempt, outcome });
                        break;
                    }
                }
            }
        }

        Ok(SendResult {
            send_port_name: send_port.name.clone(),
            status: SendStatus::Failure,
            successful_location: None,
            location_results,
            warnings,
            error: Some("all send locations failed".to_string()),
        })
    }
}
