use super::{ReceiveEndpointModule, ReceivedStream};
use crate::receive_claims::{ReceiveClaim, ReceiveClaimMode};

pub struct SftpReceiveModule;

impl ReceiveEndpointModule for SftpReceiveModule {
    fn name(&self) -> &'static str {
        "xmip.receive.sftp"
    }

    fn technology(&self) -> &'static str {
        "sftp"
    }

    fn claim(&self) -> ReceiveClaim {
        ReceiveClaim {
            mode: ReceiveClaimMode::Exclusive,
            resource: "sftp-orders-remote-path".to_string(),
        }
    }

    fn receive(&self) -> ReceivedStream {
        ReceivedStream {
            source_address: "sftp-orders-remote-path".to_string(),
            content_type: "remote-file".to_string(),
            body: "order_id=1001; customer_id=SE-42; priority=high; destination=email,archive".to_string(),
        }
    }
}
