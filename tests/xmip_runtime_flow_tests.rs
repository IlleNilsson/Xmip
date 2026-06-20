use xmip_linear_kernel::xmip_message_model::PromotedProperty;
use xmip_linear_kernel::xmip_runtime_flow::{
    authorize, promote, receive_stream, subscribe, transform, ReceiveCommand,
};

fn receive_command() -> ReceiveCommand {
    ReceiveCommand {
        cluster_name: "cluster-a".to_string(),
        node_name: "node-a".to_string(),
        receive_port: "receivePort:orders".to_string(),
        receive_location: "receiveLocation:file-in".to_string(),
        sender_identity: "partner-a".to_string(),
        content_type: "text/plain".to_string(),
        stream_reference: "stream://orders/1".to_string(),
    }
}

#[test]
fn runtime_flow_creates_lineage_and_audit() {
    let envelope = receive_stream(receive_command()).expect("receive should work");
    let envelope = authorize(envelope, "authz", true).expect("authorization should work");
    let envelope = promote(
        envelope,
        vec![
            PromotedProperty::new("message.type", "order"),
            PromotedProperty::new("priority", "high"),
            PromotedProperty::new("destination", "orders-out"),
        ],
    )
    .expect("promotion should work");
    let envelope = transform(envelope, "application/json", "stream://orders/1/json")
        .expect("transformation should work");
    let envelope = subscribe(envelope).expect("subscription should work");

    assert!(envelope.interchange.messages.len() >= 3);
    assert!(envelope.interchange.audit.len() >= 5);
    assert!(envelope.subscriptions.contains(&"process:order-orchestration".to_string()));
    assert!(envelope.subscriptions.contains(&"process:priority-monitoring".to_string()));
    assert!(envelope.subscriptions.contains(&"sendPort:orders-out".to_string()));
}

#[test]
fn runtime_flow_rejects_empty_identity() {
    let mut command = receive_command();
    command.sender_identity.clear();

    assert!(receive_stream(command).is_err());
}

#[test]
fn authorization_can_stop_flow() {
    let envelope = receive_stream(receive_command()).expect("receive should work");
    let result = authorize(envelope, "authz", false);

    assert!(result.is_err());
}
