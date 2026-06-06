#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPort {
    pub name: String,
    pub locations: Vec<SendLocation>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendLocation {
    pub name: String,
    pub address: String,
    pub technology: SendTechnology,
    pub identity: OutboundIdentity,
    pub requires_identity: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OutboundIdentity {
    Anonymous,
    UserName { name: String },
    Certificate { subject: String },
    Token { subject: String },
    ServicePrincipal { name: String },
}

impl OutboundIdentity {
    pub fn is_present(&self) -> bool {
        !matches!(self, OutboundIdentity::Anonymous)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendTechnology {
    Http,
    File,
    Queue,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendRequest {
    pub payload: String,
    pub content_type: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendOutcome {
    Sent { location: String, identity: OutboundIdentity },
    Failed { location: String, reason: String, retryable: bool },
}

pub fn send_via_port(port: &SendPort, request: &SendRequest) -> Vec<SendOutcome> {
    port.locations
        .iter()
        .map(|location| send_to_location(location, request))
        .collect()
}

fn send_to_location(location: &SendLocation, request: &SendRequest) -> SendOutcome {
    if location.address.is_empty() {
        return SendOutcome::Failed {
            location: location.name.clone(),
            reason: "missing send location address".to_string(),
            retryable: false,
        };
    }

    if request.payload.is_empty() {
        return SendOutcome::Failed {
            location: location.name.clone(),
            reason: "missing payload".to_string(),
            retryable: false,
        };
    }

    if location.requires_identity && !location.identity.is_present() {
        return SendOutcome::Failed {
            location: location.name.clone(),
            reason: "missing outbound identity".to_string(),
            retryable: false,
        };
    }

    SendOutcome::Sent {
        location: location.name.clone(),
        identity: location.identity.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn send_port_sends_to_all_locations() {
        let port = SendPort {
            name: "orders-out".to_string(),
            locations: vec![
                SendLocation {
                    name: "orders-http".to_string(),
                    address: "http-orders".to_string(),
                    technology: SendTechnology::Http,
                    identity: OutboundIdentity::Token { subject: "xmip-orders".to_string() },
                    requires_identity: true,
                },
                SendLocation {
                    name: "orders-archive".to_string(),
                    address: "file-orders".to_string(),
                    technology: SendTechnology::File,
                    identity: OutboundIdentity::ServicePrincipal { name: "xmip-file-agent".to_string() },
                    requires_identity: true,
                },
            ],
        };
        let request = SendRequest { payload: "order".to_string(), content_type: "text/plain".to_string() };

        let outcomes = send_via_port(&port, &request);

        assert_eq!(outcomes.len(), 2);
        assert!(matches!(outcomes[0], SendOutcome::Sent { .. }));
        assert!(matches!(outcomes[1], SendOutcome::Sent { .. }));
    }

    #[test]
    fn send_location_can_require_identity() {
        let port = SendPort {
            name: "secure-out".to_string(),
            locations: vec![SendLocation {
                name: "secure-http".to_string(),
                address: "secure-http-orders".to_string(),
                technology: SendTechnology::Http,
                identity: OutboundIdentity::Anonymous,
                requires_identity: true,
            }],
        };
        let request = SendRequest { payload: "order".to_string(), content_type: "text/plain".to_string() };

        let outcomes = send_via_port(&port, &request);

        assert!(matches!(outcomes[0], SendOutcome::Failed { .. }));
    }
}
