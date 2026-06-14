use prost::Message;

#[derive(Clone, PartialEq, Message)]
pub struct RuntimeSection {
    #[prost(string, tag = "1")]
    pub section_id: String,
    #[prost(string, tag = "2")]
    pub stream_reference: String,
    #[prost(bytes, tag = "3")]
    pub stream_bytes: Vec<u8>,
}

#[derive(Clone, PartialEq, Message)]
pub struct RuntimeMessage {
    #[prost(string, tag = "1")]
    pub message_id: String,
    #[prost(string, repeated, tag = "2")]
    pub interchange_chain: Vec<String>,
    #[prost(string, tag = "3")]
    pub current_interchange_id: String,
    #[prost(message, repeated, tag = "4")]
    pub sections: Vec<RuntimeSection>,
    #[prost(string, repeated, tag = "5")]
    pub promoted_properties: Vec<String>,
}

#[derive(Clone, PartialEq, Message)]
pub struct RuntimeInterchange {
    #[prost(string, tag = "1")]
    pub interchange_id: String,
    #[prost(string, tag = "2")]
    pub parent_interchange_id: String,
    #[prost(string, tag = "3")]
    pub root_interchange_id: String,
    #[prost(string, repeated, tag = "4")]
    pub message_ids: Vec<String>,
    #[prost(string, repeated, tag = "5")]
    pub events: Vec<String>,
}
