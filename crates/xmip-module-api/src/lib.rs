use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const XMIP_MODULE_ABI_VERSION: u32 = 1;
pub const XMIP_MODULE_ENTRYPOINT: &str = "xmip_create_module_v1";

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

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ModuleAbiDescriptor {
    pub abi_version: u32,
    pub module_kind: ModuleAbiKind,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ModuleAbiKind {
    TransportHandler = 1,
    ContentHandler = 2,
    LogicHandler = 3,
    StoreProvider = 4,
    ManagementModule = 5,
}

pub fn validate_module_abi(descriptor: ModuleAbiDescriptor) -> Result<(), String> {
    if descriptor.abi_version != XMIP_MODULE_ABI_VERSION {
        return Err(format!(
            "unsupported module ABI version {}; expected {}",
            descriptor.abi_version, XMIP_MODULE_ABI_VERSION
        ));
    }

    Ok(())
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
