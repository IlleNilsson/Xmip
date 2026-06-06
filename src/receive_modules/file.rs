use super::{ReceiveEndpointModule, ReceivedStream};

pub struct FileReceiveModule;

impl ReceiveEndpointModule for FileReceiveModule {
    fn name(&self) -> &'static str {
        "xmip.receive.file"
    }

    fn technology(&self) -> &'static str {
        "file"
    }

    fn receive(&self) -> ReceivedStream {
        ReceivedStream {
            source_address: "orders-file-endpoint".to_string(),
            content_type: "text-plain".to_string(),
            body: "order_id=1001; customer_id=SE-42; priority=high; destination=email,archive".to_string(),
        }
    }
}
