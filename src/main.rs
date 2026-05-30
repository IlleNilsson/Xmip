use prost::{Enumeration, Message};
use std::fs;
use std::path::Path;
use uuid::Uuid;

const CHECKPOINT_FILE: &str = "execution-context.pb";
const CRASH_MARKER_FILE: &str = "crash-once.marker";

/// Protobuf-compatible runtime state.
///
/// This is intentionally the kernel boundary. Endpoint implementations may be
/// written in Rust, C#, PowerShell, Python, shell scripts, or other technologies,
/// but the runtime truth crossing the boundary is this protobuf/gRPC-compatible
/// execution context.
#[derive(Clone, PartialEq, Message)]
pub struct ExecutionContext {
    #[prost(string, tag = "1")]
    pub execution_id: String,
    #[prost(enumeration = "Step", tag = "2")]
    pub current_step: i32,
    #[prost(uint32, tag = "3")]
    pub generation: u32,
    #[prost(string, tag = "4")]
    pub ingress_stream: String,
    #[prost(string, tag = "5")]
    pub message_body: String,
    #[prost(string, tag = "6")]
    pub transformed_body: String,
    #[prost(string, repeated, tag = "7")]
    pub promoted_properties: Vec<String>,
    #[prost(string, repeated, tag = "8")]
    pub subscriptions: Vec<String>,
    #[prost(string, repeated, tag = "9")]
    pub completed_processes: Vec<String>,
    #[prost(string, repeated, tag = "10")]
    pub send_locations: Vec<String>,
    #[prost(string, repeated, tag = "11")]
    pub lineage: Vec<String>,
    #[prost(string, repeated, tag = "12")]
    pub preservation_log: Vec<String>,

    #[prost(string, tag = "13")]
    pub receive_location: String,
    #[prost(string, tag = "14")]
    pub receive_port: String,
    #[prost(string, tag = "15")]
    pub endpoint_technology: String,
    #[prost(string, tag = "16")]
    pub message_format: String,
    #[prost(string, tag = "17")]
    pub send_port: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Enumeration)]
#[repr(i32)]
pub enum Step {
    Unspecified = 0,
    ReceiveLocation = 1,
    ReceivePort = 2,
    Analyze = 3,
    Deserialize = 4,
    Promote = 5,
    Publish = 6,
    ProcessLane = 7,
    DeliveryLane = 8,
    SendOut = 9,
    Complete = 10,
}

fn main() {
    println!("Xmip Linear Kernel 0.1.2");
    println!("Architecture-aligned protobuf recovery demo\n");

    let mut ctx = load_or_create_execution();

    loop {
        let step = Step::try_from(ctx.current_step).unwrap_or(Step::Unspecified);
        println!("Current step: {:?}", step);

        match step {
            Step::ReceiveLocation => receive_location(&mut ctx),
            Step::ReceivePort => receive_port(&mut ctx),
            Step::Analyze => analyze(&mut ctx),
            Step::Deserialize => deserialize(&mut ctx),
            Step::Promote => promote(&mut ctx),
            Step::Publish => publish(&mut ctx),
            Step::ProcessLane => process_lane(&mut ctx),
            Step::DeliveryLane => delivery_lane(&mut ctx),
            Step::SendOut => send_out(&mut ctx),
            Step::Complete => {
                complete(&ctx);
                break;
            }
            Step::Unspecified => panic!("invalid state: STEP_UNSPECIFIED"),
        }

        persist_checkpoint(&ctx);
    }
}

fn new_execution() -> ExecutionContext {
    ExecutionContext {
        execution_id: Uuid::new_v4().to_string(),
        current_step: Step::ReceiveLocation as i32,
        generation: 0,
        ingress_stream: String::new(),
        message_body: String::new(),
        transformed_body: String::new(),
        promoted_properties: Vec::new(),
        subscriptions: Vec::new(),
        completed_processes: Vec::new(),
        send_locations: Vec::new(),
        lineage: vec!["ExecutionCreated".to_string()],
        preservation_log: vec!["PreservationStarted".to_string()],
        receive_location: String::new(),
        receive_port: String::new(),
        endpoint_technology: String::new(),
        message_format: String::new(),
        send_port: String::new(),
    }
}

fn load_or_create_execution() -> ExecutionContext {
    if Path::new(CHECKPOINT_FILE).exists() {
        let bytes = fs::read(CHECKPOINT_FILE).expect("failed to read checkpoint");
        let mut ctx = ExecutionContext::decode(bytes.as_slice())
            .expect("failed to decode protobuf checkpoint");

        ctx.generation += 1;
        ctx.lineage.push(format!("RecoveredGeneration{}", ctx.generation));
        ctx.preservation_log
            .push(format!("RecoveredFromCheckpointGeneration{}", ctx.generation));

        println!("Recovered execution from protobuf checkpoint.");
        println!("ExecutionId: {}", ctx.execution_id);
        println!("Generation: {}\n", ctx.generation);

        ctx
    } else {
        let ctx = new_execution();
        println!("Created new execution.");
        println!("ExecutionId: {}\n", ctx.execution_id);
        persist_checkpoint(&ctx);
        ctx
    }
}

fn persist_checkpoint(ctx: &ExecutionContext) {
    let mut buffer = Vec::new();
    ctx.encode(&mut buffer)
        .expect("failed to encode protobuf execution context");
    fs::write(CHECKPOINT_FILE, buffer).expect("failed to persist checkpoint");

    let step = Step::try_from(ctx.current_step).unwrap_or(Step::Unspecified);
    println!("Checkpoint persisted as protobuf buffer at boundary: {:?}\n", step);
}

fn preserve(ctx: &mut ExecutionContext, event: &str) {
    ctx.preservation_log.push(event.to_string());
}

fn receive_location(ctx: &mut ExecutionContext) {
    println!("Stream arrives at receiveLocation.");

    ctx.receive_location = "receiveLocation:orders/inbound-script".to_string();
    ctx.endpoint_technology = "external-script-or-language-endpoint".to_string();

    // Xmip starts here. The endpoint may be implemented by another language or
    // script technology, but Xmip receives the stream and makes it durable.
    ctx.ingress_stream = "order_id=1001; customer_id=SE-42; priority=high; destination=email,archive,webhook; body=hello from xmip linear".to_string();

    ctx.lineage.push("ReceiveLocationCompleted".to_string());
    preserve(ctx, "IngressStreamPreservedAtReceiveLocation");
    ctx.current_step = Step::ReceivePort as i32;
}

fn receive_port(ctx: &mut ExecutionContext) {
    println!("Binding stream to receivePort.");

    if ctx.ingress_stream.is_empty() {
        panic!("missing ingress stream");
    }

    ctx.receive_port = "receivePort:orders".to_string();

    ctx.lineage.push("ReceivePortBound".to_string());
    preserve(ctx, "ReceivePortBindingPreserved");
    ctx.current_step = Step::Analyze as i32;
}

fn analyze(ctx: &mut ExecutionContext) {
    println!("Analyzing stream and detecting format.");

    if ctx.ingress_stream.trim().starts_with('{') {
        ctx.message_format = "json".to_string();
    } else if ctx.ingress_stream.trim().starts_with('<') {
        ctx.message_format = "xml".to_string();
    } else if ctx.ingress_stream.contains('=') && ctx.ingress_stream.contains(';') {
        ctx.message_format = "key-value-flat-stream".to_string();
    } else {
        ctx.message_format = "unknown".to_string();
    }

    if ctx.message_format == "unknown" {
        panic!("unable to determine message format");
    }

    ctx.lineage
        .push(format!("AnalyzeCompleted:format={}", ctx.message_format));
    preserve(ctx, "FormatDetectionPreserved");
    ctx.current_step = Step::Deserialize as i32;
}

fn deserialize(ctx: &mut ExecutionContext) {
    println!("Deserializing stream into an understandable message.");

    if ctx.ingress_stream.is_empty() {
        panic!("missing ingress stream");
    }

    // Minimal demo deserializer. Real handlers will live behind explicit
    // content/contract handlers, potentially implemented in different runtimes.
    ctx.message_body = ctx.ingress_stream.clone();

    ctx.lineage.push("DeserializeCompleted".to_string());
    preserve(ctx, "MessageBodyPreserved");
    ctx.current_step = Step::Promote as i32;
}

fn promote(ctx: &mut ExecutionContext) {
    println!("Promoting properties for subscription matching.");

    ctx.promoted_properties = vec![
        "message.type=order".to_string(),
        "priority=high".to_string(),
        "customer.region=SE".to_string(),
        "destination=email".to_string(),
        "destination=archive".to_string(),
        "destination=webhook".to_string(),
    ];

    ctx.lineage.push("PromoteCompleted".to_string());
    preserve(ctx, "PromotedPropertiesIndexed");
    ctx.current_step = Step::Publish as i32;
}

fn publish(ctx: &mut ExecutionContext) {
    println!("Publishing immutable message to subscription fabric.");

    ctx.subscriptions = resolve_subscriptions(&ctx.promoted_properties);

    println!("Matched subscriptions:");
    for sub in &ctx.subscriptions {
        println!("  - {}", sub);
    }

    ctx.lineage.push("PublishCompleted".to_string());
    preserve(ctx, "PublicationPreserved");
    ctx.current_step = Step::ProcessLane as i32;

    if !Path::new(CRASH_MARKER_FILE).exists() {
        fs::write(CRASH_MARKER_FILE, "crashed once").expect("failed to write crash marker");

        persist_checkpoint(ctx);
        panic!("Simulated crash after Publish boundary. Run again to recover.");
    }
}

fn resolve_subscriptions(properties: &[String]) -> Vec<String> {
    let mut subscriptions = Vec::new();

    if properties.iter().any(|p| p == "message.type=order") {
        subscriptions.push("process:order-orchestration".to_string());
    }

    if properties.iter().any(|p| p == "priority=high") {
        subscriptions.push("process:priority-monitoring".to_string());
    }

    if properties.iter().any(|p| p == "customer.region=SE") {
        subscriptions.push("process:regional-audit".to_string());
    }

    if properties.iter().any(|p| p.starts_with("destination=")) {
        subscriptions.push("sendPort:orders-out".to_string());
    }

    subscriptions
}

fn process_lane(ctx: &mut ExecutionContext) {
    println!("Executing process/orchestration subscriptions.");

    let process_subscriptions: Vec<String> = ctx
        .subscriptions
        .iter()
        .filter(|s| s.starts_with("process:"))
        .cloned()
        .collect();

    for process in process_subscriptions {
        println!("Process executed: {}", process);
        ctx.completed_processes.push(process.clone());
        ctx.lineage.push(format!("ProcessCompleted:{}", process));
        preserve(ctx, &format!("ProcessStatePreserved:{}", process));
    }

    ctx.current_step = Step::DeliveryLane as i32;
}

fn delivery_lane(ctx: &mut ExecutionContext) {
    println!("Preparing sendPort delivery lane from subscriptions.");

    let has_send_port_subscription = ctx
        .subscriptions
        .iter()
        .any(|s| s == "sendPort:orders-out");

    if has_send_port_subscription {
        ctx.send_port = "sendPort:orders-out".to_string();

        // Optional delivery-side transformation. Transformation is not required
        // before promotion/publish; it belongs to process or delivery semantics.
        ctx.transformed_body = ctx.message_body.to_uppercase();
        ctx.lineage
            .push("DeliveryTransformCompleted:orders-out".to_string());
        preserve(ctx, "DeliveryTransformPreserved");

        ctx.send_locations = vec![
            "sendLocation:email".to_string(),
            "sendLocation:archive".to_string(),
            "sendLocation:webhook".to_string(),
        ];
    }

    for location in &ctx.send_locations {
        println!("Delivery prepared: {}", location);
    }

    ctx.lineage.push("DeliveryLanePrepared".to_string());
    preserve(ctx, "DeliveryPlanPreserved");
    ctx.current_step = Step::SendOut as i32;
}

fn send_out(ctx: &mut ExecutionContext) {
    println!("Sending to all resolved sendLocation(s).");

    let send_locations = ctx.send_locations.clone();
    let payload = if ctx.transformed_body.is_empty() {
        &ctx.message_body
    } else {
        &ctx.transformed_body
    };

    for location in send_locations {
        println!("Sent to {}", location);
        println!("Payload: {}", payload);
        ctx.lineage.push(format!("SendCompleted:{}", location));
        ctx.preservation_log.push(format!("SendRecorded:{}", location));
    }

    ctx.current_step = Step::Complete as i32;
}

fn complete(ctx: &ExecutionContext) {
    println!("\nExecution complete.");
    println!("ExecutionId: {}", ctx.execution_id);
    println!("Generation: {}", ctx.generation);
    println!("ReceiveLocation: {}", ctx.receive_location);
    println!("ReceivePort: {}", ctx.receive_port);
    println!("MessageFormat: {}", ctx.message_format);
    println!("SendPort: {}", ctx.send_port);

    println!("\nLineage:");
    for item in &ctx.lineage {
        println!("  - {}", item);
    }

    println!("\nPreservation log:");
    for item in &ctx.preservation_log {
        println!("  - {}", item);
    }
}
