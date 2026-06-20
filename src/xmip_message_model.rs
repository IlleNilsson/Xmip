use std::collections::BTreeMap;
use std::time::SystemTime;
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CreationKind {
    Receive,
    Assignment,
    Transformation,
    Process,
    Send,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CreationInstance {
    pub kind: CreationKind,
    pub name: String,
    pub cluster_name: String,
    pub node_name: String,
    pub when_utc: SystemTime,
}

impl CreationInstance {
    pub fn new(kind: CreationKind, name: impl Into<String>, cluster: impl Into<String>, node: impl Into<String>) -> Self {
        Self {
            kind,
            name: name.into(),
            cluster_name: cluster.into(),
            node_name: node.into(),
            when_utc: SystemTime::now(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PromotedProperty {
    pub name: String,
    pub value: String,
}

impl PromotedProperty {
    pub fn new(name: impl Into<String>, value: impl Into<String>) -> Self {
        Self { name: name.into(), value: value.into() }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Section {
    pub section_id: Uuid,
    pub creation: CreationInstance,
    pub content_type: String,
    pub stream_reference: String,
}

impl Section {
    pub fn new(creation: CreationInstance, content_type: impl Into<String>, stream_reference: impl Into<String>) -> Self {
        Self {
            section_id: Uuid::new_v4(),
            creation,
            content_type: content_type.into(),
            stream_reference: stream_reference.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Message {
    pub interchange_id: Uuid,
    pub message_id: Uuid,
    pub parent_message_id: Option<Uuid>,
    pub creation: CreationInstance,
    pub sections: Vec<Section>,
    pub promoted_properties: Vec<PromotedProperty>,
}

impl Message {
    pub fn receive(creation: CreationInstance, sections: Vec<Section>) -> Self {
        Self {
            interchange_id: Uuid::new_v4(),
            message_id: Uuid::new_v4(),
            parent_message_id: None,
            creation,
            sections,
            promoted_properties: Vec::new(),
        }
    }

    pub fn with_promoted_property(mut self, property: PromotedProperty) -> Self {
        self.promoted_properties.push(property);
        self
    }

    pub fn transform(&self, creation: CreationInstance, sections: Vec<Section>) -> Self {
        Self {
            interchange_id: self.interchange_id,
            message_id: Uuid::new_v4(),
            parent_message_id: Some(self.message_id),
            creation,
            sections,
            promoted_properties: self.promoted_properties.clone(),
        }
    }

    pub fn assign(&self, creation: CreationInstance, promoted_properties: Vec<PromotedProperty>) -> Self {
        let mut merged = self.promoted_properties.clone();
        merged.extend(promoted_properties);

        Self {
            interchange_id: self.interchange_id,
            message_id: Uuid::new_v4(),
            parent_message_id: Some(self.message_id),
            creation,
            sections: self.sections.clone(),
            promoted_properties: merged,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuditAction {
    Receive,
    IdentityLookup,
    Authentication,
    Authorization,
    Promotion,
    Transformation,
    Assignment,
    Subscription,
    Orchestration,
    Process,
    Send,
    Success,
    Failure,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuditEntry {
    pub audit_id: Uuid,
    pub interchange_id: Uuid,
    pub message_id: Option<Uuid>,
    pub action: AuditAction,
    pub actor: String,
    pub outcome: String,
    pub when_utc: SystemTime,
}

impl AuditEntry {
    pub fn new(interchange_id: Uuid, message_id: Option<Uuid>, action: AuditAction, actor: impl Into<String>, outcome: impl Into<String>) -> Self {
        Self {
            audit_id: Uuid::new_v4(),
            interchange_id,
            message_id,
            action,
            actor: actor.into(),
            outcome: outcome.into(),
            when_utc: SystemTime::now(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Interchange {
    pub interchange_id: Uuid,
    pub root_message_id: Uuid,
    pub messages: BTreeMap<Uuid, Message>,
    pub audit: Vec<AuditEntry>,
}

impl Interchange {
    pub fn start(root: Message) -> Self {
        let interchange_id = root.interchange_id;
        let root_message_id = root.message_id;
        let mut messages = BTreeMap::new();
        messages.insert(root.message_id, root);

        Self { interchange_id, root_message_id, messages, audit: Vec::new() }
    }

    pub fn add_message(&mut self, message: Message) -> Result<(), String> {
        if message.interchange_id != self.interchange_id {
            return Err("message belongs to another interchange".to_string());
        }

        self.messages.insert(message.message_id, message);
        Ok(())
    }

    pub fn add_audit(&mut self, entry: AuditEntry) -> Result<(), String> {
        if entry.interchange_id != self.interchange_id {
            return Err("audit entry belongs to another interchange".to_string());
        }

        self.audit.push(entry);
        Ok(())
    }
}
