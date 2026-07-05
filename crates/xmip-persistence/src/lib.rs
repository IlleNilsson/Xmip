use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DurableRecordIdentity {
    pub cluster_name: String,
    pub node_name: String,
    pub interchange_id: Uuid,
    pub message_id: Uuid,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DurableExecutionCheckpoint {
    pub identity: DurableRecordIdentity,
    pub xmip_process_name: Option<String>,
    pub current_step: String,
    pub generation: u32,
    pub payload_refs: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeduplicationRecord {
    pub interchange_id: Uuid,
    pub message_id: Uuid,
    pub source_fingerprint: String,
}

pub trait RuntimeStore {
    fn persist_checkpoint(&self, checkpoint: DurableExecutionCheckpoint) -> Result<(), String>;
    fn load_checkpoint(&self, identity: &DurableRecordIdentity) -> Result<Option<DurableExecutionCheckpoint>, String>;
    fn remember_deduplication(&self, record: DeduplicationRecord) -> Result<(), String>;
}
