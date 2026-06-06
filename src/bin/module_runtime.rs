#[path = "../receive_claims.rs"]
mod receive_claims;
#[path = "../receive_modules.rs"]
mod receive_modules;
#[path = "../receive_security.rs"]
mod receive_security;

use receive_claims::ReceiveClaimRegistry;
use receive_modules::load_receive_module;
use receive_security::{authorize_receive, IdentityEvidence, ReceiveIdentity, ReceivePermission};
use std::env;

#[derive(Debug, Clone, PartialEq, Eq)]
enum RuntimeStep {
    Receive,
    Authorize,
    Accept,
    Promote,
    Publish,
    Execute,
    Complete,
}

#[derive(Debug, Clone)]
struct RuntimeContext {
    step: RuntimeStep,
    endpoint_module: String,
    endpoint_technology: String,
    source_address: String,
    content_type: String,
    stream: String,
    identity: Option<ReceiveIdentity>,
    xmip_message: Option<String>,
    promoted_properties: Vec<String>,
    subscriptions: Vec<String>,
    outputs: Vec<String>,
    audit: Vec<String>,
}

impl RuntimeContext {
    fn new() -> Self {
        Self {
            step: RuntimeStep::Receive,
            endpoint_module: String::new(),
            endpoint_technology: String::new(),
            source_address: String::new(),
            content_type: String::new(),
            stream: String::new(),
            identity: None,
            xmip_message: None,
            promoted_properties: Vec::new(),
            subscriptions: Vec::new(),
            outputs: Vec::new(),
            audit: vec!["RuntimeStarted".to_string()],
        }
    }
}

fn main() {
    let endpoint = env::args().nth(1).unwrap_or_else(|| "http".to_string());
    let module = load_receive_module(&endpoint);
    let mut claims = ReceiveClaimRegistry::new();
    let mut ctx = RuntimeContext::new();

    ctx.endpoint_module = module.name().to_string();
    ctx.endpoint_technology = module.technology().to_string();
    ctx.audit.push(format!("ReceiveModuleLoaded:{}", module.name()));

    if let Err(error) = claims.claim(&module.claim()) {
        ctx.audit.push(format!("Failure:ReceiveClaimRejected:{error}"));
        ctx.outputs.push("ReceiveClaimRejected".to_string());
        print_summary(&ctx);
        return;
    }

    ctx.audit.push(format!("ReceiveClaimAccepted:{:?}", module.claim()));

    loop {
        match ctx.step {
            RuntimeStep::Receive => {
                let received = module.receive();
                ctx.source_address = received.source_address;
                ctx.content_type = received.content_type;
                ctx.stream = received.body;
                ctx.identity = Some(identify_receive_source(&ctx));
                ctx.audit.push("ExternalStreamReceived".to_string());
                ctx.step = RuntimeStep::Authorize;
            }
            RuntimeStep::Authorize => {
                let identity = ctx.identity.as_ref().expect("receive identity missing");
                let receive_decision = authorize_receive(identity, ReceivePermission::ReceiveFromEndpoint);
                let accept_decision = authorize_receive(identity, ReceivePermission::AcceptStream);

                ctx.audit.push(format!("Authorization:ReceiveFromEndpoint:{}", receive_decision.reason));
                ctx.audit.push(format!("Authorization:AcceptStream:{}", accept_decision.reason));

                if receive_decision.allowed && accept_decision.allowed {
                    ctx.step = RuntimeStep::Accept;
                } else {
                    ctx.outputs.push("Reject:UnauthorizedReceive".to_string());
                    ctx.audit.push("Failure:UnauthorizedReceiveRejected".to_string());
                    ctx.step = RuntimeStep::Complete;
                }
            }
            RuntimeStep::Accept => {
                ctx.xmip_message = Some(ctx.stream.clone());
                ctx.audit.push("Accept:XmipMessageCreated".to_string());
                ctx.step = RuntimeStep::Promote;
            }
            RuntimeStep::Promote => {
                ctx.promoted_properties.push("message.type=order".to_string());
                ctx.promoted_properties.push("priority=high".to_string());
                for part in ctx.stream.split(';') {
                    let trimmed = part.trim();
                    if trimmed.starts_with("destination=") {
                        ctx.promoted_properties.push(trimmed.to_string());
                    }
                }
                ctx.audit.push("PromoteCompleted".to_string());
                ctx.step = RuntimeStep::Publish;
            }
            RuntimeStep::Publish => {
                let identity = ctx.identity.as_ref().expect("receive identity missing");
                let publish_decision = authorize_receive(identity, ReceivePermission::PublishIntoXmip);
                ctx.audit.push(format!("Authorization:PublishIntoXmip:{}", publish_decision.reason));

                if !publish_decision.allowed {
                    ctx.outputs.push("Reject:UnauthorizedPublish".to_string());
                    ctx.audit.push("Failure:UnauthorizedPublishRejected".to_string());
                    ctx.step = RuntimeStep::Complete;
                    continue;
                }

                if ctx.promoted_properties.iter().any(|p| p == "message.type=order") {
                    ctx.subscriptions.push("process:order-business-process".to_string());
                }
                if ctx.promoted_properties.iter().any(|p| p.starts_with("destination=")) {
                    ctx.subscriptions.push("sendPort:orders-out".to_string());
                }
                if ctx.subscriptions.is_empty() {
                    ctx.outputs.push("XmipDMQ".to_string());
                    ctx.audit.push("NoSubscriptionMatched:XmipDMQ".to_string());
                    ctx.step = RuntimeStep::Complete;
                } else {
                    ctx.audit.push(format!("SubscriptionsMatched:{}", ctx.subscriptions.len()));
                    ctx.step = RuntimeStep::Execute;
                }
            }
            RuntimeStep::Execute => {
                for subscription in ctx.subscriptions.clone() {
                    if subscription.starts_with("process:") {
                        ctx.outputs.push(format!("Completed:{subscription}"));
                        ctx.audit.push(format!("ProcessCompleted:{subscription}"));
                    }
                    if subscription.starts_with("sendPort:") {
                        for property in &ctx.promoted_properties {
                            if let Some(destinations) = property.strip_prefix("destination=") {
                                for destination in destinations.split(',') {
                                    ctx.outputs.push(format!("Sent:sendLocation:{destination}"));
                                }
                            }
                        }
                        ctx.audit.push(format!("SendPortCompleted:{subscription}"));
                    }
                }
                ctx.step = RuntimeStep::Complete;
            }
            RuntimeStep::Complete => break,
        }
    }

    print_summary(&ctx);
}

fn identify_receive_source(ctx: &RuntimeContext) -> ReceiveIdentity {
    let evidence = match ctx.endpoint_technology.as_str() {
        "http" | "webhook" => IdentityEvidence::TokenSubject("demo-http-client".to_string()),
        "file" | "ftp" | "sftp" | "ftps" => IdentityEvidence::ServicePrincipal("demo-file-agent".to_string()),
        "msmq" | "rabbitmq" => IdentityEvidence::ServicePrincipal("demo-queue-consumer".to_string()),
        _ => IdentityEvidence::NetworkPeer(ctx.source_address.clone()),
    };

    ReceiveIdentity {
        evidence,
        authenticated: true,
    }
}

fn print_summary(ctx: &RuntimeContext) {
    println!("EndpointModule: {}", ctx.endpoint_module);
    println!("EndpointTechnology: {}", ctx.endpoint_technology);
    println!("SourceAddress: {}", ctx.source_address);
    println!("ContentType: {}", ctx.content_type);
    println!("Identity: {:?}", ctx.identity);

    println!("\nOutputs:");
    for output in &ctx.outputs {
        println!("  - {output}");
    }

    println!("\nAudit:");
    for event in &ctx.audit {
        println!("  - {event}");
    }
}
