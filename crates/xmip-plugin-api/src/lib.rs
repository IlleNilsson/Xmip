use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PluginIdentity {
    pub name: String,
    pub version: String,
    pub kind: PluginKind,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum PluginKind {
    TransportHandler,
    ContentHandler,
    LogicHandler,
    StoreProvider,
    ManagementExtension,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PluginCapability {
    pub capability: String,
    pub execution_host: ExecutionHostKind,
    pub low_latency_capable: bool,
    pub trusted_required: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ExecutionHostKind {
    NativeRust,
    DotNet,
    Java,
    Python,
    CAbi,
    Go,
    PowerShell,
    Bash,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PluginManifest {
    pub identity: PluginIdentity,
    pub capabilities: Vec<PluginCapability>,
    pub entrypoint: PluginEntrypoint,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PluginEntrypoint {
    pub library_path: Option<String>,
    pub executable_path: Option<String>,
    pub symbol: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct HandlerInvocation {
    pub invocation_id: Uuid,
    pub interchange_id: Uuid,
    pub message_id: Uuid,
    pub artifact_name: String,
    pub location_name: Option<String>,
    pub payload_ref: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct HandlerResult {
    pub invocation_id: Uuid,
    pub status: HandlerStatus,
    pub output_payload_ref: Option<String>,
    pub promoted_properties: Vec<(String, String)>,
    pub diagnostic: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum HandlerStatus {
    Completed,
    RetryableFailure,
    NonRetryableFailure,
}

pub trait XmipPlugin: Send + Sync {
    fn manifest(&self) -> &PluginManifest;
}

pub trait TransportHandler: XmipPlugin {
    fn receive(&self, invocation: HandlerInvocation) -> HandlerResult;
    fn send(&self, invocation: HandlerInvocation) -> HandlerResult;
}

pub trait ContentHandler: XmipPlugin {
    fn deserialize(&self, invocation: HandlerInvocation) -> HandlerResult;
    fn serialize(&self, invocation: HandlerInvocation) -> HandlerResult;
}
