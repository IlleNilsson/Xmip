#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuntimeStage {
    Receive,
    Interpret,
    Publish,
    Dispatch,
    Store,
    Handler,
    Configure,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StageRecord {
    pub stage: RuntimeStage,
    pub name: String,
    pub message_id: Option<String>,
    pub interchange_id: Option<String>,
}

impl StageRecord {
    pub fn new(stage: RuntimeStage, name: impl Into<String>) -> Self {
        Self {
            stage,
            name: name.into(),
            message_id: None,
            interchange_id: None,
        }
    }

    pub fn message(mut self, message_id: impl Into<String>) -> Self {
        self.message_id = Some(message_id.into());
        self
    }

    pub fn interchange(mut self, interchange_id: impl Into<String>) -> Self {
        self.interchange_id = Some(interchange_id.into());
        self
    }
}
