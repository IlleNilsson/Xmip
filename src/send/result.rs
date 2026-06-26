use crate::send::transport::SendAttemptOutcome;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendStatus {
    Success,
    SuccessWithWarnings,
    Failure,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendLocationResult {
    pub location_name: String,
    pub attempts: u32,
    pub outcome: SendAttemptOutcome,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPortResult {
    pub send_port_name: String,
    pub status: SendStatus,
    pub successful_location: Option<String>,
    pub location_results: Vec<SendLocationResult>,
    pub warnings: Vec<String>,
    pub error: Option<String>,
}

pub type SendResult = SendPortResult;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPortGroupResult {
    pub group_name: String,
    pub port_results: Vec<SendPortResult>,
    pub status: SendStatus,
}
