use super::{SendEndpointModule, SendOutcome, SendRequest};

pub struct HttpSendModule;

impl SendEndpointModule for HttpSendModule {
    fn name(&self) -> &'static str {
        "xmip.send.http"
    }

    fn technology(&self) -> &'static str {
        "http"
    }

    fn send(&self, request: &SendRequest) -> SendOutcome {
        if request.location.is_empty() {
            SendOutcome::Failed { reason: "missing http destination".to_string(), retryable: false }
        } else {
            SendOutcome::Sent
        }
    }
}
