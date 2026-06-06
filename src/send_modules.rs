pub mod file;
pub mod http;
pub mod queue;

use file::FileSendModule;
use http::HttpSendModule;
use queue::QueueSendModule;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendRequest {
    pub location: String,
    pub content_type: String,
    pub payload: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SendOutcome {
    Sent,
    Failed { reason: String, retryable: bool },
}

pub trait SendEndpointModule {
    fn name(&self) -> &'static str;
    fn technology(&self) -> &'static str;
    fn send(&self, request: &SendRequest) -> SendOutcome;
}

pub fn load_send_module(name: &str) -> Box<dyn SendEndpointModule> {
    match name {
        "file" => Box::new(FileSendModule),
        "http" => Box::new(HttpSendModule),
        "queue" => Box::new(QueueSendModule),
        other => panic!("unknown send endpoint module: {other}"),
    }
}
