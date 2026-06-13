#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessDefinition {
    pub name: String,
    pub stages: Vec<ProcessStageDefinition>,
    pub outcomes: Vec<ProcessOutcome>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessStageDefinition {
    pub name: String,
    pub awaits: Vec<String>,
    pub may_create_messages: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessInstance {
    pub instance_id: String,
    pub definition_name: String,
    pub state: ProcessState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessState {
    pub current_stage: String,
    pub status: ProcessStatus,
    pub correlation_keys: Vec<String>,
    pub waiting_for: Vec<String>,
    pub active_interchange_chain: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProcessStatus {
    Running,
    Waiting,
    Completed,
    CompletedWithWarnings,
    Failed,
    Cancelled,
    TimedOut,
    Abandoned,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProcessOutcome {
    Completed,
    CompletedWithWarnings,
    Failed,
    Cancelled,
    TimedOut,
    Abandoned,
}

impl ProcessInstance {
    pub fn start(
        instance_id: String,
        definition: &ProcessDefinition,
        initial_interchange_chain: Vec<String>,
    ) -> Self {
        let first_stage = definition
            .stages
            .first()
            .map(|stage| stage.name.clone())
            .unwrap_or_else(|| "start".to_string());

        Self {
            instance_id,
            definition_name: definition.name.clone(),
            state: ProcessState {
                current_stage: first_stage,
                status: ProcessStatus::Running,
                correlation_keys: Vec::new(),
                waiting_for: Vec::new(),
                active_interchange_chain: initial_interchange_chain,
            },
        }
    }

    pub fn wait_for(&mut self, expected_message: String) {
        self.state.status = ProcessStatus::Waiting;
        self.state.waiting_for.push(expected_message);
    }

    pub fn resume_with_interchange_chain(&mut self, interchange_chain: Vec<String>) {
        self.state.status = ProcessStatus::Running;
        self.state.active_interchange_chain = interchange_chain;
    }
}
