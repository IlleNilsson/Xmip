#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendLocation {
    pub name: String,
    pub target_uri: String,
    pub retry_count: u32,
}

impl SendLocation {
    pub fn new(name: impl Into<String>, target_uri: impl Into<String>, retry_count: u32) -> Self {
        SendLocation {
            name: name.into(),
            target_uri: target_uri.into(),
            retry_count,
        }
    }
}
