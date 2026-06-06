use super::{ReceiveEndpointModule, ReceivedStream};
use crate::receive_claims::{ReceiveClaim, ReceiveClaimMode};

pub struct FtpReceiveModule;

impl ReceiveEndpointModule for FtpReceiveModule {
    fn name(&self) -> &'static str {
        "xmip.receive.ftp"
    }

    fn technology(&self) -> &'static str {
        "ftp"
    }

    fn claim(&self) -> ReceiveClaim {
        ReceiveClaim {
            mode: ReceiveClaimMode::Exclusive,
            resource: "ftp-orders-remote-path".to_string(),
        }
    }

    fn receive(&self) -> ReceivedStream {
        ReceivedStream {
            source_address: "ftp-orders-remote-path".to_string(),
            content_type: "remote-file".to_string(),
            body: "order_id=1001; customer_id=SE-42; priority=high; destination=email,archive".to_string(),
        }
    }
}
