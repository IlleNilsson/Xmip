pub trait ReceiveEndpointModule {
    fn name(&self) -> &'static str;
    fn technology(&self) -> &'static str;
    fn receive(&self) -> ReceivedStream;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceivedStream {
    pub source_address: String,
    pub content_type: String,
    pub body: String,
}

pub struct HttpReceiveModule;
pub struct FileReceiveModule;

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

pub fn load_receive_module(name: &str) -> Box<dyn ReceiveEndpointModule> {
    match name {
        "file" => Box::new(FileReceiveModule),
        _ => Box::new(HttpReceiveModule),
    }
}
