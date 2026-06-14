#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPortDefinition {
    pub name: String,
    pub send_locations: Vec<SendLocationDefinition>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendLocationDefinition {
    pub name: String,
    pub handler_reference: String,
    pub handler_configuration: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPortGroupDefinition {
    pub name: String,
    pub send_ports: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendLocationOutcome {
    Succeeded,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendLocationInstance {
    pub instance_id: String,
    pub definition_name: String,
    pub message_id: String,
    pub interchange_chain: Vec<String>,
    pub outcome: SendLocationOutcome,
    pub warning_or_failure: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendPortOutcome {
    Running,
    Completed,
    CompletedWithWarnings,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPortInstance {
    pub instance_id: String,
    pub definition_name: String,
    pub message_id: String,
    pub interchange_chain: Vec<String>,
    pub attempted_locations: Vec<SendLocationInstance>,
    pub outcome: SendPortOutcome,
}

impl SendPortInstance {
    pub fn new(
        instance_id: String,
        definition: &SendPortDefinition,
        message_id: String,
        interchange_chain: Vec<String>,
    ) -> Self {
        Self {
            instance_id,
            definition_name: definition.name.clone(),
            message_id,
            interchange_chain,
            attempted_locations: Vec::new(),
            outcome: SendPortOutcome::Running,
        }
    }

    pub fn record_location_result(&mut self, location: SendLocationInstance) {
        self.attempted_locations.push(location);

        let any_success = self
            .attempted_locations
            .iter()
            .any(|item| item.outcome == SendLocationOutcome::Succeeded);

        let any_failure = self
            .attempted_locations
            .iter()
            .any(|item| item.outcome == SendLocationOutcome::Failed);

        if any_success && any_failure {
            self.outcome = SendPortOutcome::CompletedWithWarnings;
        } else if any_success {
            self.outcome = SendPortOutcome::Completed;
        }
    }

    pub fn mark_failed_if_no_location_succeeded(&mut self) {
        let any_success = self
            .attempted_locations
            .iter()
            .any(|item| item.outcome == SendLocationOutcome::Succeeded);

        if !any_success {
            self.outcome = SendPortOutcome::Failed;
        }
    }
}
