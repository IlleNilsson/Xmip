use super::{ReceiveEndpointModule, ReceivedStream};
use crate::receive_claims::{ReceiveClaim, ReceiveClaimMode};

pub struct MsmqReceiveModule;

impl ReceiveEndpointModule for MsmqReceiveModule {
    fn name(&self) -> &'static str {
        "xmip.receive.msmq"
    }

    fn technology(&self) -> &'static str {
        "msmq"
    }

    fn claim(&self) -> ReceiveClaim {
        ReceiveClaim {
            mode: ReceiveClaimMode::Pattern,
            resource: "queue-orders|subject=order.created".to_string(),
        }
    }

    fn receive(&self) -> ReceivedStream {
        ReceivedStream {
            source_address: "queue-orders".to_string(),
            content_type: "queue-message".to_string(),
            body: "subject=order.created; order_id=1001; customer_id=SE-42; priority=high; destination=email,archive".to_string(),
        }
    }
}
