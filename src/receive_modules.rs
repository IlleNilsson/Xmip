pub mod file;
pub mod http;
pub mod msmq;
pub mod rabbitmq;

use crate::receive_claims::ReceiveClaim;
use file::FileReceiveModule;
use http::HttpReceiveModule;
use msmq::MsmqReceiveModule;
use rabbitmq::RabbitMqReceiveModule;

pub trait ReceiveEndpointModule {
    fn name(&self) -> &'static str;
    fn technology(&self) -> &'static str;
    fn claim(&self) -> ReceiveClaim;
    fn receive(&self) -> ReceivedStream;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceivedStream {
    pub source_address: String,
    pub content_type: String,
    pub body: String,
}

pub fn load_receive_module(name: &str) -> Box<dyn ReceiveEndpointModule> {
    match name {
        "file" => Box::new(FileReceiveModule),
        "http" => Box::new(HttpReceiveModule),
        "msmq" => Box::new(MsmqReceiveModule),
        "rabbitmq" => Box::new(RabbitMqReceiveModule),
        other => panic!("unknown receive endpoint module: {other}. Use 'http', 'file', 'msmq', or 'rabbitmq'."),
    }
}
