use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub use xmip_module_abi::{
    validate_module_abi, ModuleAbiDescriptor, ModuleAbiKind, XMIP_MODULE_ABI_VERSION,
    XMIP_MODULE_ENTRYPOINT,
};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleIdentity {
    pub name: String,
    pub version: String,
    pub kind: ModuleKind,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ModuleKind {
    TransportHandler,
    ContentHandler,
    LogicHandler,
    StoreProvider,
    ManagementModule,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleCapability {
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
pub struct ModuleManifest {
    pub identity: ModuleIdentity,
    pub capabilities: Vec<ModuleCapability>,
    pub entrypoint: ModuleEntrypoint,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleEntrypoint {
    pub library_path: Option<String>,
    pub executable_path: Option<String>,
    pub symbol: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExtensionManifest {
    pub name: String,
    pub version: String,
    pub execution_host: ExecutionHostKind,
    pub entrypoint: ExtensionEntrypoint,
    pub required_capabilities: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExtensionEntrypoint {
    pub path: String,
    pub symbol_or_command: Option<String>,
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

pub trait XmipModule: Send + Sync {
    fn manifest(&self) -> &ModuleManifest;
}

pub trait TransportHandler: XmipModule {
    fn receive(&self, invocation: HandlerInvocation) -> HandlerResult;
    fn send(&self, invocation: HandlerInvocation) -> HandlerResult;
}

pub trait ContentHandler: XmipModule {
    fn deserialize(&self, invocation: HandlerInvocation) -> HandlerResult;
    fn serialize(&self, invocation: HandlerInvocation) -> HandlerResult;
}
