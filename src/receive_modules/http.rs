use super::{ReceiveEndpointModule, ReceivedStream};
use crate::receive_claims::{ReceiveClaim, ReceiveClaimMode};

pub struct HttpReceiveModule;

impl ReceiveEndpointModule for HttpReceiveModule {
    fn name(&self) -> &'static str {
        "xmip.receive.http"
    }

    fn technology(&self) -> &'static str {
        "http"
    }

    fn claim(&self) -> ReceiveClaim {
        ReceiveClaim {
            mode: ReceiveClaimMode::Shared,
            resource: "http-listener".to_string(),
        }
    }

    fn receive(&self) -> ReceivedStream {
        ReceivedStream {
            source_address: "orders-http-endpoint".to_string(),
            content_type: "application-x-www-form-urlencoded".to_string(),
            body: "order_id=1001; customer_id=SE-42; priority=high; destination=email,archive,webhook".to_string(),
        }
    }
}
