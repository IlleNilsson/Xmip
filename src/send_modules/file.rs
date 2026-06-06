use super::{SendEndpointModule, SendOutcome, SendRequest};

pub struct FileSendModule;

impl SendEndpointModule for FileSendModule {
    fn name(&self) -> &'static str {
        "xmip.send.file"
    }

    fn technology(&self) -> &'static str {
        "file"
    }

    fn send(&self, request: &SendRequest) -> SendOutcome {
        if request.location.is_empty() {
            SendOutcome::Failed { reason: "missing file destination".to_string(), retryable: false }
        } else {
            SendOutcome::Sent
        }
    }
}
