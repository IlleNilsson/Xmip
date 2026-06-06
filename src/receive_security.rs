#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IdentityEvidence {
    Anonymous,
    CertificateSubject(String),
    TokenSubject(String),
    UserName(String),
    ServicePrincipal(String),
    NetworkPeer(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiveIdentity {
    pub evidence: IdentityEvidence,
    pub authenticated: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceivePermission {
    ReceiveFromEndpoint,
    AcceptStream,
    UseContract,
    PublishIntoXmip,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuthorizationDecision {
    pub allowed: bool,
    pub reason: String,
}

pub fn authorize_receive(identity: &ReceiveIdentity, permission: ReceivePermission) -> AuthorizationDecision {
    if !identity.authenticated {
        return AuthorizationDecision {
            allowed: false,
            reason: "identity not authenticated".to_string(),
        };
    }

    AuthorizationDecision {
        allowed: true,
        reason: format!("authorized for {:?}", permission),
    }
}
