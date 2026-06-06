use super::{SendEndpointModule, SendOutcome, SendRequest};

pub struct QueueSendModule;

impl SendEndpointModule for QueueSendModule {
    fn name(&self) -> &'static str {
        "xmip.send.queue"
    }

    fn technology(&self) -> &'static str {
        "queue"
    }

    fn send(&self, request: &SendRequest) -> SendOutcome {
        if request.location.is_empty() {
            SendOutcome::Failed { reason: "missing queue destination".to_string(), retryable: false }
        } else {
            SendOutcome::Sent
        }
    }
}
