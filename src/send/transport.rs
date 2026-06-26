use crate::send::location::SendLocation;
use crate::xmip_message_model::Message;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendFailureKind {
    Retryable,
    NonRetryable,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendAttemptOutcome {
    Success,
    Failure { kind: SendFailureKind, reason: String },
}

pub trait SendTransport {
    fn send(&self, location: &SendLocation, message: &Message) -> SendAttemptOutcome;
}
