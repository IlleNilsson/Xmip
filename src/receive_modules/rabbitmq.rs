use super::{ReceiveEndpointModule, ReceivedStream};
use crate::receive_claims::{ReceiveClaim, ReceiveClaimMode};

pub struct RabbitMqReceiveModule;

impl ReceiveEndpointModule for RabbitMqReceiveModule {
    fn name(&self) -> &'static str {
        "xmip.receive.rabbitmq"
    }

    fn technology(&self) -> &'static str {
        "rabbitmq"
    }

    fn claim(&self) -> ReceiveClaim {
        ReceiveClaim {
            mode: ReceiveClaimMode::Pattern,
            resource: "queue-orders|routing_key=order.created".to_string(),
        }
    }

    fn receive(&self) -> ReceivedStream {
        ReceivedStream {
            source_address: "queue-orders".to_string(),
            content_type: "queue-message".to_string(),
            body: "routing_key=order.created; order_id=1001; customer_id=SE-42; priority=high; destination=email,archive,webhook".to_string(),
        }
    }
}
