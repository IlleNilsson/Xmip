use super::{ReceiveEndpointModule, ReceivedStream};
use crate::receive_claims::{ReceiveClaim, ReceiveClaimMode};

pub struct WebHookReceiveModule;

impl ReceiveEndpointModule for WebHookReceiveModule {
    fn name(&self) -> &'static str {
        "xmip.receive.webhook"
    }

    fn technology(&self) -> &'static str {
        "webhook"
    }

    fn claim(&self) -> ReceiveClaim {
        ReceiveClaim {
            mode: ReceiveClaimMode::Shared,
            resource: "webhook-listener".to_string(),
        }
    }

    fn receive(&self) -> ReceivedStream {
        ReceivedStream {
            source_address: "orders-webhook-endpoint".to_string(),
            content_type: "application-json".to_string(),
            body: "subject=order.created; order_id=1001; customer_id=SE-42; priority=high; destination=email,archive,webhook".to_string(),
        }
    }
}
