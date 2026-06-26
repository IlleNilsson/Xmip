use crate::xmip_message_model::{
    AuditAction, AuditEntry, CreationInstance, CreationKind, Interchange, Message, PromotedProperty,
    Section,
};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendIdentity {
    pub name: String,
}

impl SendIdentity {
    pub fn new(name: impl Into<String>) -> Self {
        Self { name: name.into() }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendLocation {
    pub name: String,
    pub target_uri: String,
    pub retry_count: u32,
    pub identity: Option<SendIdentity>,
}

impl SendLocation {
    pub fn new(name: impl Into<String>, target_uri: impl Into<String>, retry_count: u32) -> Self {
        Self {
            name: name.into(),
            target_uri: target_uri.into(),
            retry_count,
            identity: None,
        }
    }

    pub fn with_identity(mut self, identity: SendIdentity) -> Self {
        self.identity = Some(identity);
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPort {
    pub name: String,
    pub locations: Vec<SendLocation>,
    pub identity: Option<SendIdentity>,
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
            identity: None,
            send_side_promotions: Vec::new(),
            send_side_transform_content_type: None,
        })
    }

    pub fn with_identity(mut self, identity: SendIdentity) -> Self {
        self.identity = Some(identity);
        self
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
pub struct SendPortGroup {
    pub name: String,
    pub ports: Vec<SendPort>,
    pub identity: Option<SendIdentity>,
}

impl SendPortGroup {
    pub fn new(name: impl Into<String>, ports: Vec<SendPort>) -> Result<Self, String> {
        if ports.is_empty() {
            return Err("send port group requires at least one send port".to_string());
        }

        Ok(Self {
            name: name.into(),
            ports,
            identity: None,
        })
    }

    pub fn with_identity(mut self, identity: SendIdentity) -> Self {
        self.identity = Some(identity);
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
    Failure {
        kind: SendFailureKind,
        reason: String,
    },
}

pub trait SendTransport {
    fn send(
        &self,
        location: &SendLocation,
        message: &Message,
        identity: &SendIdentity,
    ) -> SendAttemptOutcome;
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
    pub exposed_identity: SendIdentity,
    pub attempts: u32,
    pub outcome: SendAttemptOutcome,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPortResult {
    pub send_port_name: String,
    pub status: SendStatus,
    pub successful_location: Option<String>,
    pub location_results: Vec<SendLocationResult>,
    pub warnings: Vec<String>,
    pub error: Option<String>,
}

pub type SendResult = SendPortResult;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPortGroupResult {
    pub group_name: String,
    pub port_results: Vec<SendPortResult>,
    pub status: SendStatus,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendExecutionContext {
    pub process_identity: SendIdentity,
    pub group_identity: Option<SendIdentity>,
}

impl SendExecutionContext {
    pub fn new(process_identity: SendIdentity) -> Self {
        Self {
            process_identity,
            group_identity: None,
        }
    }

    pub fn with_group_identity(mut self, identity: Option<SendIdentity>) -> Self {
        self.group_identity = identity;
        self
    }

    fn resolve_identity(&self, port: &SendPort, location: &SendLocation) -> SendIdentity {
        location
            .identity
            .clone()
            .or_else(|| port.identity.clone())
            .or_else(|| self.group_identity.clone())
            .unwrap_or_else(|| self.process_identity.clone())
    }
}

pub struct SendRuntime;

impl SendRuntime {
    pub fn execute_port<T: SendTransport>(
        interchange: &mut Interchange,
        source_message_id: Uuid,
        send_port: &SendPort,
        transport: &T,
    ) -> Result<SendPortResult, String> {
        let context = SendExecutionContext::new(SendIdentity::new("xmip-sending-process"));
        Self::execute_port_with_context(interchange, source_message_id, send_port, &context, transport)
    }

    pub fn execute_port_with_identity<T: SendTransport>(
        interchange: &mut Interchange,
        source_message_id: Uuid,
        send_port: &SendPort,
        process_identity: SendIdentity,
        transport: &T,
    ) -> Result<SendPortResult, String> {
        let context = SendExecutionContext::new(process_identity);
        Self::execute_port_with_context(interchange, source_message_id, send_port, &context, transport)
    }

    pub fn execute_port_with_context<T: SendTransport>(
        interchange: &mut Interchange,
        source_message_id: Uuid,
        send_port: &SendPort,
        context: &SendExecutionContext,
        transport: &T,
    ) -> Result<SendPortResult, String> {
        let mut working_message = interchange
            .messages
            .get(&source_message_id)
            .ok_or_else(|| "source message not found".to_string())?
            .clone();

        if !send_port.send_side_promotions.is_empty() {
            working_message = working_message.assign(
                CreationInstance::new(
                    CreationKind::Assignment,
                    format!("send-promotion:{}", send_port.name),
                    "cluster",
                    "node",
                ),
                send_port.send_side_promotions.clone(),
            );
            interchange.add_message(working_message.clone())?;
            interchange.add_audit(AuditEntry::new(
                interchange.interchange_id,
                Some(working_message.message_id),
                AuditAction::Promotion,
                send_port.name.clone(),
                "send-side promotion",
            ))?;
        }

        if let Some(content_type) = &send_port.send_side_transform_content_type {
            let creation = CreationInstance::new(
                CreationKind::Transformation,
                format!("send-transform:{}", send_port.name),
                "cluster",
                "node",
            );
            let section = Section::new(
                creation.clone(),
                content_type.clone(),
                format!("send://{}/payload", send_port.name),
            );
            working_message = working_message.transform(creation, vec![section]);
            interchange.add_message(working_message.clone())?;
            interchange.add_audit(AuditEntry::new(
                interchange.interchange_id,
                Some(working_message.message_id),
                AuditAction::Transformation,
                send_port.name.clone(),
                "send-side transform",
            ))?;
        }

        let mut warnings = Vec::new();
        let mut location_results = Vec::new();

        for location in &send_port.locations {
            let identity = context.resolve_identity(send_port, location);
            let mut attempt = 0;

            loop {
                attempt += 1;
                let outcome = transport.send(location, &working_message, &identity);

                match &outcome {
                    SendAttemptOutcome::Success => {
                        interchange.add_audit(AuditEntry::new(
                            interchange.interchange_id,
                            Some(working_message.message_id),
                            AuditAction::Send,
                            location.name.clone(),
                            format!("success; identity={}", identity.name),
                        ))?;
                        location_results.push(SendLocationResult {
                            location_name: location.name.clone(),
                            exposed_identity: identity,
                            attempts: attempt,
                            outcome,
                        });

                        let status = if warnings.is_empty() {
                            SendStatus::Success
                        } else {
                            SendStatus::SuccessWithWarnings
                        };

                        return Ok(SendPortResult {
                            send_port_name: send_port.name.clone(),
                            status,
                            successful_location: Some(location.name.clone()),
                            location_results,
                            warnings,
                            error: None,
                        });
                    }
                    SendAttemptOutcome::Failure {
                        kind: SendFailureKind::Retryable,
                        reason,
                    } => {
                        if attempt <= location.retry_count {
                            continue;
                        }

                        let error = format!(
                            "{} failed after retryable retries using identity {}: {}",
                            location.name, identity.name, reason
                        );
                        interchange.add_audit(AuditEntry::new(
                            interchange.interchange_id,
                            Some(working_message.message_id),
                            AuditAction::Failure,
                            location.name.clone(),
                            error.clone(),
                        ))?;
                        location_results.push(SendLocationResult {
                            location_name: location.name.clone(),
                            exposed_identity: identity,
                            attempts: attempt,
                            outcome,
                        });

                        return Ok(SendPortResult {
                            send_port_name: send_port.name.clone(),
                            status: SendStatus::Failure,
                            successful_location: None,
                            location_results,
                            warnings,
                            error: Some(error),
                        });
                    }
                    SendAttemptOutcome::Failure {
                        kind: SendFailureKind::NonRetryable,
                        reason,
                    } => {
                        let warning = format!(
                            "{} non-retryable failure using identity {}; trying next send location: {}",
                            location.name, identity.name, reason
                        );
                        warnings.push(warning.clone());
                        interchange.add_audit(AuditEntry::new(
                            interchange.interchange_id,
                            Some(working_message.message_id),
                            AuditAction::Failure,
                            location.name.clone(),
                            warning,
                        ))?;
                        location_results.push(SendLocationResult {
                            location_name: location.name.clone(),
                            exposed_identity: identity,
                            attempts: attempt,
                            outcome,
                        });
                        break;
                    }
                }
            }
        }

        Ok(SendPortResult {
            send_port_name: send_port.name.clone(),
            status: SendStatus::Failure,
            successful_location: None,
            location_results,
            warnings,
            error: Some("all send locations failed".to_string()),
        })
    }

    pub fn execute_group<T: SendTransport>(
        interchange: &mut Interchange,
        source_message_id: Uuid,
        group: &SendPortGroup,
        transport: &T,
    ) -> Result<SendPortGroupResult, String> {
        Self::execute_group_with_identity(
            interchange,
            source_message_id,
            group,
            SendIdentity::new("xmip-sending-process"),
            transport,
        )
    }

    pub fn execute_group_with_identity<T: SendTransport>(
        interchange: &mut Interchange,
        source_message_id: Uuid,
        group: &SendPortGroup,
        process_identity: SendIdentity,
        transport: &T,
    ) -> Result<SendPortGroupResult, String> {
        let mut port_results = Vec::new();

        for port in &group.ports {
            let context = SendExecutionContext::new(process_identity.clone())
                .with_group_identity(group.identity.clone());
            port_results.push(Self::execute_port_with_context(
                interchange,
                source_message_id,
                port,
                &context,
                transport,
            )?);
        }

        let status = if port_results
            .iter()
            .all(|result| result.status == SendStatus::Success)
        {
            SendStatus::Success
        } else if port_results
            .iter()
            .any(|result| result.status != SendStatus::Failure)
        {
            SendStatus::SuccessWithWarnings
        } else {
            SendStatus::Failure
        };

        Ok(SendPortGroupResult {
            group_name: group.name.clone(),
            port_results,
            status,
        })
    }

    pub fn execute<T: SendTransport>(
        interchange: &mut Interchange,
        source_message_id: Uuid,
        send_port: &SendPort,
        transport: &T,
    ) -> Result<SendPortResult, String> {
        Self::execute_port(interchange, source_message_id, send_port, transport)
    }
}
