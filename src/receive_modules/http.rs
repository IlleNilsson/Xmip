use super::{ReceiveEndpointModule, ReceivedStream};

pub struct HttpReceiveModule;

impl ReceiveEndpointModule for HttpReceiveModule {
    fn name(&self) -> &'static str {
        "xmip.receive.http"
    }

    fn technology(&self) -> &'static str {
        "http"
    }

    fn receive(&self) -> ReceivedStream {
        ReceivedStream {
            source_address: "orders-http-endpoint".to_string(),
            content_type: "application-x-www-form-urlencoded".to_string(),
            body: "order_id=1001; customer_id=SE-42; priority=high; destination=email,archive,webhook".to_string(),
        }
    }
}
