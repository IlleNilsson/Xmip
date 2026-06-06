pub mod file;
pub mod ftp;
pub mod ftps;
pub mod http;
pub mod msmq;
pub mod rabbitmq;
pub mod sftp;
pub mod webhook;

use crate::receive_claims::ReceiveClaim;
use file::FileReceiveModule;
use ftp::FtpReceiveModule;
use ftps::FtpsReceiveModule;
use http::HttpReceiveModule;
use msmq::MsmqReceiveModule;
use rabbitmq::RabbitMqReceiveModule;
use sftp::SftpReceiveModule;
use webhook::WebHookReceiveModule;

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
        "ftp" => Box::new(FtpReceiveModule),
        "ftps" => Box::new(FtpsReceiveModule),
        "http" => Box::new(HttpReceiveModule),
        "msmq" => Box::new(MsmqReceiveModule),
        "rabbitmq" => Box::new(RabbitMqReceiveModule),
        "sftp" => Box::new(SftpReceiveModule),
        "webhook" => Box::new(WebHookReceiveModule),
        other => panic!("unknown receive endpoint module: {other}"),
    }
}
