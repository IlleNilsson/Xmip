use crate::runtime_message::RuntimeMessage;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum HandlerKind {
    Receive,
    Send,
    Content,
    Logic,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HandlerDescriptor {
    pub name: String,
    pub kind: HandlerKind,
    pub module_name: String,
}

pub trait Handler: Send + Sync {
    fn descriptor(&self) -> HandlerDescriptor;
}

pub trait ReceiveHandler: Handler {
    fn receive(&self) -> Result<RuntimeMessage, HandlerError>;
}

pub trait SendHandler: Handler {
    fn send(&self, message: &RuntimeMessage) -> Result<(), HandlerError>;
}

pub trait ContentHandler: Handler {
    fn interpret(&self, message: RuntimeMessage) -> Result<RuntimeMessage, HandlerError>;
}

pub trait LogicHandler: Handler {
    fn execute(&self, message: RuntimeMessage) -> Result<RuntimeMessage, HandlerError>;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HandlerError {
    pub handler_name: String,
    pub message: String,
}
