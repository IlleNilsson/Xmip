use xmip_linear_kernel::xmip_message_model::{
    AuditAction, AuditEntry, CreationInstance, CreationKind, Interchange, Message,
    PromotedProperty, Section,
};

fn creation(kind: CreationKind, name: &str) -> CreationInstance {
    CreationInstance::new(kind, name, "cluster-a", "node-a")
}

#[test]
fn receive_creates_new_interchange_and_message() {
    let receive = creation(CreationKind::Receive, "receivePort:orders");
    let section = Section::new(receive.clone(), "text/plain", "stream://orders/1");
    let message = Message::receive(receive, vec![section]);

    assert_eq!(message.parent_message_id, None);
    assert_eq!(message.sections.len(), 1);
}

#[test]
fn transform_creates_new_message_in_same_interchange() {
    let receive = creation(CreationKind::Receive, "receivePort:orders");
    let section = Section::new(receive.clone(), "text/plain", "stream://orders/1");
    let message = Message::receive(receive, vec![section])
        .with_promoted_property(PromotedProperty::new("message.type", "order"));

    let transform = creation(CreationKind::Transformation, "normalize-order");
    let transformed_section = Section::new(transform.clone(), "application/json", "stream://orders/1/json");
    let transformed = message.transform(transform, vec![transformed_section]);

    assert_eq!(transformed.interchange_id, message.interchange_id);
    assert_ne!(transformed.message_id, message.message_id);
    assert_eq!(transformed.parent_message_id, Some(message.message_id));
    assert_eq!(transformed.promoted_properties, message.promoted_properties);
}

#[test]
fn assignment_creates_new_message_with_extra_promotions() {
    let receive = creation(CreationKind::Receive, "receivePort:orders");
    let section = Section::new(receive.clone(), "text/plain", "stream://orders/1");
    let message = Message::receive(receive, vec![section])
        .with_promoted_property(PromotedProperty::new("message.type", "order"));

    let assigned = message.assign(
        creation(CreationKind::Assignment, "assign-priority"),
        vec![PromotedProperty::new("priority", "high")],
    );

    assert_eq!(assigned.interchange_id, message.interchange_id);
    assert_ne!(assigned.message_id, message.message_id);
    assert_eq!(assigned.parent_message_id, Some(message.message_id));
    assert_eq!(assigned.promoted_properties.len(), 2);
}

#[test]
fn interchange_rejects_foreign_messages_and_audit() {
    let receive = creation(CreationKind::Receive, "receivePort:orders");
    let message = Message::receive(
        receive.clone(),
        vec![Section::new(receive, "text/plain", "stream://orders/1")],
    );
    let mut interchange = Interchange::start(message);

    let other_receive = creation(CreationKind::Receive, "receivePort:other");
    let foreign_message = Message::receive(
        other_receive.clone(),
        vec![Section::new(other_receive, "text/plain", "stream://other/1")],
    );

    assert!(interchange.add_message(foreign_message).is_err());

    let foreign_audit = AuditEntry::new(
        uuid::Uuid::new_v4(),
        None,
        AuditAction::Failure,
        "test",
        "foreign",
    );

    assert!(interchange.add_audit(foreign_audit).is_err());
}

#[test]
fn audit_can_be_added_to_interchange() {
    let receive = creation(CreationKind::Receive, "receivePort:orders");
    let message = Message::receive(
        receive.clone(),
        vec![Section::new(receive, "text/plain", "stream://orders/1")],
    );
    let message_id = message.message_id;
    let interchange_id = message.interchange_id;
    let mut interchange = Interchange::start(message);

    let audit = AuditEntry::new(
        interchange_id,
        Some(message_id),
        AuditAction::Receive,
        "receivePort:orders",
        "success",
    );

    interchange.add_audit(audit).expect("audit should belong to interchange");
    assert_eq!(interchange.audit.len(), 1);
}
