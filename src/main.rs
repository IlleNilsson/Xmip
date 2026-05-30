use prost::{Enumeration, Message};
use std::fs;
use std::path::Path;
use uuid::Uuid;

const CHECKPOINT_FILE: &str = "execution-context.pb";
const CRASH_MARKER_FILE: &str = "crash-once.marker";

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
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Enumeration)]
#[repr(i32)]
pub enum Step {
    Unspecified = 0,
    StreamIn = 1,
    Deserialize = 2,
    Transform = 3,
    Promote = 4,
    Publish = 5,
    ProcessLane = 6,
    DeliveryLane = 7,
    SendOut = 8,
    Complete = 9,
}

fn main() {
    println!("Xmip Linear Kernel 0.1.1");
    println!("Subscription-driven protobuf recovery demo\n");

    let mut ctx = load_or_create_execution();

    loop {
        let step = Step::try_from(ctx.current_step).unwrap_or(Step::Unspecified);
        println!("Current step: {:?}", step);

        match step {
            Step::StreamIn => stream_in(&mut ctx),
            Step::Deserialize => deserialize(&mut ctx),
            Step::Transform => transform(&mut ctx),
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
        current_step: Step::StreamIn as i32,
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
    }
}

fn load_or_create_execution() -> ExecutionContext {
    if Path::new(CHECKPOINT_FILE).exists() {
        let bytes = fs::read(CHECKPOINT_FILE).expect("failed to read checkpoint");
        let mut ctx = ExecutionContext::decode(bytes.as_slice())
            .expect("failed to decode protobuf checkpoint");

        ctx.generation += 1;
        ctx.lineage.push(format!("RecoveredGeneration{}", ctx.generation));
        ctx.preservation_log.push(format!("RecoveredFromCheckpointGeneration{}", ctx.generation));

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
    fs::write(CHECKPOINT_FILE, buffer)
        .expect("failed to persist checkpoint");

    let step = Step::try_from(ctx.current_step).unwrap_or(Step::Unspecified);
    println!("Checkpoint persisted as protobuf buffer at boundary: {:?}\n", step);
}

fn preserve(ctx: &mut ExecutionContext, event: &str) {
    ctx.preservation_log.push(event.to_string());
}

fn stream_in(ctx: &mut ExecutionContext) {
    println!("Stream enters Xmip at receive location.");

    ctx.ingress_stream = "order_id=1001; customer_id=SE-42; priority=high; destination=email,archive,webhook; body=hello from xmip linear".to_string();

    ctx.lineage.push("StreamInCompleted".to_string());
    preserve(ctx, "IngressStreamPreserved");
    ctx.current_step = Step::Deserialize as i32;
}

fn deserialize(ctx: &mut ExecutionContext) {
    println!("Deserializing stream into understandable message.");

    if ctx.ingress_stream.is_empty() {
        panic!("missing ingress stream");
    }

    ctx.message_body = ctx.ingress_stream.clone();

    ctx.lineage.push("DeserializeCompleted".to_string());
    preserve(ctx, "MessageBodyPreserved");
    ctx.current_step = Step::Transform as i32;
}

fn transform(ctx: &mut ExecutionContext) {
    println!("Transforming message after deserialization.");

    if ctx.message_body.is_empty() {
        panic!("missing message body");
    }

    ctx.transformed_body = ctx.message_body.to_uppercase();

    ctx.lineage.push("TransformCompleted".to_string());
    preserve(ctx, "TransformedMessagePreserved");
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
        fs::write(CRASH_MARKER_FILE, "crashed once")
            .expect("failed to write crash marker");

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
        subscriptions.push("delivery:direct-send".to_string());
    }

    subscriptions
}

fn process_lane(ctx: &mut ExecutionContext) {
    println!("Executing process lane subscriptions.");

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
    println!("Preparing delivery lane from subscriptions.");

    let has_direct_delivery = ctx
        .subscriptions
        .iter()
        .any(|s| s == "delivery:direct-send");

    if has_direct_delivery {
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
    println!("Sending to all resolved destinations.");

    let send_locations = ctx.send_locations.clone();

    for location in send_locations {
        println!("Sent to {}", location);
        ctx.lineage.push(format!("SendCompleted:{}", location));
        ctx.preservation_log.push(format!("SendRecorded:{}", location));
    }

    ctx.current_step = Step::Complete as i32;
}

fn complete(ctx: &ExecutionContext) {
    println!("\nExecution complete.");
    println!("ExecutionId: {}", ctx.execution_id);
    println!("Generation: {}", ctx.generation);

    println!("\nLineage:");
    for item in &ctx.lineage {
        println!("  - {}", item);
    }

    println!("\nPreservation log:");
    for item in &ctx.preservation_log {
        println!("  - {}", item);
    }
}
