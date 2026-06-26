use crate::send::port::SendPort;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendPortGroup {
    pub name: String,
    pub ports: Vec<SendPort>,
}

impl SendPortGroup {
    pub fn new(name: impl Into<String>, ports: Vec<SendPort>) -> Result<Self, String> {
        if ports.is_empty() {
            return Err("send port group requires at least one send port".to_string());
        }

        Ok(Self {
            name: name.into(),
            ports,
        })
    }
}
