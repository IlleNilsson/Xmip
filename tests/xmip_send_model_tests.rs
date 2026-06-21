use std::collections::VecDeque;
use std::sync::Mutex;
use xmip_linear_kernel::xmip_message_model::{CreationInstance, CreationKind, Interchange, Message, PromotedProperty, Section};
use xmip_linear_kernel::xmip_send_model::{
    SendAttemptOutcome, SendFailureKind, SendLocation, SendPort, SendRuntime, SendStatus,
    SendTransport,
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
fn send_succeeds_without_receive_runtime() {
    let (mut interchange, message_id) = source_interchange();
    let send_port = SendPort::new(
        "sendPort:orders-out",
        vec![SendLocation::primary("primary", "https://target.example/orders", 3)],
    )
    .expect("send port should be valid");
    let transport = ScriptedTransport::new(vec![SendAttemptOutcome::Success]);

    let result = SendRuntime::execute(&mut interchange, message_id, &send_port, &transport)
        .expect("send should execute");

    assert_eq!(result.status, SendStatus::Success);
    assert_eq!(result.successful_location, Some("primary".to_string()));
    assert_eq!(interchange.audit.len(), 1);
}

#[test]
fn non_retryable_failure_fails_over_to_next_location() {
    let (mut interchange, message_id) = source_interchange();
    let send_port = SendPort::new(
        "sendPort:orders-out",
        vec![
            SendLocation::primary("primary", "https://primary.example/orders", 3),
            SendLocation::secondary("secondary", "https://secondary.example/orders", 3),
        ],
    )
    .expect("send port should be valid");
    let transport = ScriptedTransport::new(vec![
        SendAttemptOutcome::Failure { kind: SendFailureKind::NonRetryable, reason: "bad endpoint".to_string() },
        SendAttemptOutcome::Success,
    ]);

    let result = SendRuntime::execute(&mut interchange, message_id, &send_port, &transport)
        .expect("send should execute");

    assert_eq!(result.status, SendStatus::SuccessWithWarnings);
    assert_eq!(result.successful_location, Some("secondary".to_string()));
    assert_eq!(result.warnings.len(), 1);
    assert_eq!(result.location_results.len(), 2);
}

#[test]
fn retryable_failure_retries_same_location_before_failure() {
    let (mut interchange, message_id) = source_interchange();
    let send_port = SendPort::new(
        "sendPort:orders-out",
        vec![SendLocation::primary("primary", "https://primary.example/orders", 2)],
    )
    .expect("send port should be valid");
    let transport = ScriptedTransport::new(vec![
        SendAttemptOutcome::Failure { kind: SendFailureKind::Retryable, reason: "timeout".to_string() },
        SendAttemptOutcome::Failure { kind: SendFailureKind::Retryable, reason: "timeout".to_string() },
        SendAttemptOutcome::Success,
    ]);

    let result = SendRuntime::execute(&mut interchange, message_id, &send_port, &transport)
        .expect("send should execute");

    assert_eq!(result.status, SendStatus::Success);
    assert_eq!(result.location_results[0].attempts, 3);
}

#[test]
fn all_locations_failed_returns_error_status() {
    let (mut interchange, message_id) = source_interchange();
    let send_port = SendPort::new(
        "sendPort:orders-out",
        vec![
            SendLocation::primary("primary", "https://primary.example/orders", 0),
            SendLocation::secondary("secondary", "https://secondary.example/orders", 0),
        ],
    )
    .expect("send port should be valid");
    let transport = ScriptedTransport::new(vec![
        SendAttemptOutcome::Failure { kind: SendFailureKind::NonRetryable, reason: "bad endpoint".to_string() },
        SendAttemptOutcome::Failure { kind: SendFailureKind::NonRetryable, reason: "bad endpoint".to_string() },
    ]);

    let result = SendRuntime::execute(&mut interchange, message_id, &send_port, &transport)
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
        vec![SendLocation::primary("primary", "https://target.example/orders", 0)],
    )
    .expect("send port should be valid")
    .with_promotion(PromotedProperty::new("destination.format", "json"))
    .with_transform("application/json");
    let transport = ScriptedTransport::new(vec![SendAttemptOutcome::Success]);

    let before = interchange.messages.len();
    let result = SendRuntime::execute(&mut interchange, message_id, &send_port, &transport)
        .expect("send should execute");

    assert_eq!(result.status, SendStatus::Success);
    assert_eq!(interchange.messages.len(), before + 2);
    assert!(interchange.audit.iter().any(|entry| entry.outcome == "send-side promotion"));
    assert!(interchange.audit.iter().any(|entry| entry.outcome == "send-side transform"));
}
