use crate::cluster_identity::XmipRuntimePlace;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuntimeRecordKind {
    ArtifactInstance,
    Message,
    SendAttempt,
    ReceiveAttempt,
    ProcessState,
    AuditFailure,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeRecord {
    pub id: String,
    pub kind: RuntimeRecordKind,
    pub place: XmipRuntimePlace,
    pub correlation_id: Option<String>,
    pub message_id: Option<String>,
    pub outcome: Option<String>,
}

impl RuntimeRecord {
    pub fn belongs_to_same_cluster_as(&self, other: &XmipRuntimePlace) -> bool {
        self.place.same_cluster_as(other)
    }
}
