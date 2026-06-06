use super::{ReceiveEndpointModule, ReceivedStream};
use crate::receive_claims::{ReceiveClaim, ReceiveClaimMode};

pub struct FtpsReceiveModule;

impl ReceiveEndpointModule for FtpsReceiveModule {
    fn name(&self) -> &'static str {
        "xmip.receive.ftps"
    }

    fn technology(&self) -> &'static str {
        "ftps"
    }

    fn claim(&self) -> ReceiveClaim {
        ReceiveClaim {
            mode: ReceiveClaimMode::Exclusive,
            resource: "ftps-orders".to_string(),
        }
    }

    fn receive(&self) -> ReceivedStream {
        ReceivedStream {
            source_address: "ftps-orders".to_string(),
            content_type: "remote-file".to_string(),
            body: "order_id=1001; priority=high; destination=email,archive".to_string(),
        }
    }
}
