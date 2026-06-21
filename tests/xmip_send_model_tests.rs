use std::collections::VecDeque;
use std::sync::Mutex;
use xmip_linear_kernel::xmip_message_model::{CreationInstance, CreationKind, Interchange, Message, PromotedProperty, Section};
use xmip_linear_kernel::xmip_send_model::{
    SendAttemptOutcome, SendFailureKind, SendLocation, SendPort, SendPortGroup, SendRuntime,
    SendStatus, SendTransport,
};

fn source_interchange() -> (Interchange, uuid::Uuid) {
    let creation = CreationInstance::new(CreationKind::Process, "process:orders", "cluster-a", "node-a");
    let section = Section::new(creation.clone(), "application/json", "stream://process/orders/1");
    let message = Message::receive(creation, vec![section])
        .with_promoted_property(PromotedProperty::new("message.type", "order"));
    let message_id = message.message_id;
    (Interchange::start(message), message_id)
}

struct ScriptedTransport {
    outcomes: Mutex<VecDeque<SendAttemptOutcome>>,
}

impl ScriptedTransport {
    fn new(outcomes: Vec<SendAttemptOutcome>) -> Self {
        Self { outcomes: Mutex::new(VecDeque::from(outcomes)) }
    }
}

impl SendTransport for ScriptedTransport {
    fn send(&self, _location: &SendLocation, _message: &Message) -> SendAttemptOutcome {
        self.outcomes
            .lock()
            .expect("transport lock")
            .pop_front()
            .unwrap_or(SendAttemptOutcome::Success)
    }
}

#[test]
fn send_port_succeeds_without_receive_runtime() {
    let (mut interchange, message_id) = source_interchange();
    let send_port = SendPort::new(
        "sendPort:orders-out",
        vec![SendLocation::new("location-a", "https://target.example/orders", 3)],
    )
    .expect("send port should be valid");
    let transport = ScriptedTransport::new(vec![SendAttemptOutcome::Success]);

    let result = SendRuntime::execute_port(&mut interchange, message_id, &send_port, &transport)
        .expect("send should execute");

    assert_eq!(result.status, SendStatus::Success);
    assert_eq!(result.successful_location, Some("location-a".to_string()));
    assert_eq!(interchange.audit.len(), 1);
}

#[test]
fn non_retryable_failure_moves_to_next_send_location_in_order() {
    let (mut interchange, message_id) = source_interchange();
    let send_port = SendPort::new(
        "sendPort:orders-out",
        vec![
            SendLocation::new("location-a", "https://a.example/orders", 3),
            SendLocation::new("location-b", "https://b.example/orders", 3),
        ],
    )
    .expect("send port should be valid");
    let transport = ScriptedTransport::new(vec![
        SendAttemptOutcome::Failure { kind: SendFailureKind::NonRetryable, reason: "bad endpoint".to_string() },
        SendAttemptOutcome::Success,
    ]);

    let result = SendRuntime::execute_port(&mut interchange, message_id, &send_port, &transport)
        .expect("send should execute");

    assert_eq!(result.status, SendStatus::SuccessWithWarnings);
    assert_eq!(result.successful_location, Some("location-b".to_string()));
    assert_eq!(result.warnings.len(), 1);
    assert_eq!(result.location_results.len(), 2);
}

#[test]
fn retryable_failure_retries_same_send_location_before_next_location() {
    let (mut interchange, message_id) = source_interchange();
    let send_port = SendPort::new(
        "sendPort:orders-out",
        vec![SendLocation::new("location-a", "https://a.example/orders", 2)],
    )
    .expect("send port should be valid");
    let transport = ScriptedTransport::new(vec![
        SendAttemptOutcome::Failure { kind: SendFailureKind::Retryable, reason: "timeout".to_string() },
        SendAttemptOutcome::Failure { kind: SendFailureKind::Retryable, reason: "timeout".to_string() },
        SendAttemptOutcome::Success,
    ]);

    let result = SendRuntime::execute_port(&mut interchange, message_id, &send_port, &transport)
        .expect("send should execute");

    assert_eq!(result.status, SendStatus::Success);
    assert_eq!(result.location_results[0].attempts, 3);
}

#[test]
fn all_send_locations_failed_returns_error_status() {
    let (mut interchange, message_id) = source_interchange();
    let send_port = SendPort::new(
        "sendPort:orders-out",
        vec![
            SendLocation::new("location-a", "https://a.example/orders", 0),
            SendLocation::new("location-b", "https://b.example/orders", 0),
        ],
    )
    .expect("send port should be valid");
    let transport = ScriptedTransport::new(vec![
        SendAttemptOutcome::Failure { kind: SendFailureKind::NonRetryable, reason: "bad endpoint".to_string() },
        SendAttemptOutcome::Failure { kind: SendFailureKind::NonRetryable, reason: "bad endpoint".to_string() },
    ]);

    let result = SendRuntime::execute_port(&mut interchange, message_id, &send_port, &transport)
        .expect("send should execute");

    assert_eq!(result.status, SendStatus::Failure);
    assert_eq!(result.error, Some("all send locations failed".to_string()));
    assert_eq!(result.warnings.len(), 2);
}

#[test]
fn send_side_promotion_and_transform_create_new_messages() {
    let (mut interchange, message_id) = source_interchange();
    let send_port = SendPort::new(
        "sendPort:orders-out",
        vec![SendLocation::new("location-a", "https://target.example/orders", 0)],
    )
    .expect("send port should be valid")
    .with_promotion(PromotedProperty::new("destination.format", "json"))
    .with_transform("application/json");
    let transport = ScriptedTransport::new(vec![SendAttemptOutcome::Success]);

    let before = interchange.messages.len();
    let result = SendRuntime::execute_port(&mut interchange, message_id, &send_port, &transport)
        .expect("send should execute");

    assert_eq!(result.status, SendStatus::Success);
    assert_eq!(interchange.messages.len(), before + 2);
    assert!(interchange.audit.iter().any(|entry| entry.outcome == "send-side promotion"));
    assert!(interchange.audit.iter().any(|entry| entry.outcome == "send-side transform"));
}

#[test]
fn send_port_group_executes_independent_send_ports() {
    let (mut interchange, message_id) = source_interchange();
    let port_a = SendPort::new(
        "sendPort:archive",
        vec![SendLocation::new("archive-location", "file:///archive/orders", 0)],
    )
    .expect("send port should be valid");
    let port_b = SendPort::new(
        "sendPort:webhook",
        vec![SendLocation::new("webhook-location", "https://webhook.example/orders", 0)],
    )
    .expect("send port should be valid");
    let group = SendPortGroup::new("sendPortGroup:orders", vec![port_a, port_b])
        .expect("send port group should be valid");
    let transport = ScriptedTransport::new(vec![SendAttemptOutcome::Success, SendAttemptOutcome::Success]);

    let result = SendRuntime::execute_group(&mut interchange, message_id, &group, &transport)
        .expect("send port group should execute");

    assert_eq!(result.status, SendStatus::Success);
    assert_eq!(result.port_results.len(), 2);
}
