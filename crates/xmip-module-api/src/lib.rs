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

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContentHandlerInvocation {
    pub invocation: HandlerInvocation,
    pub operation: ContentOperation,
    pub requested_properties: Vec<ContentPropertySelector>,
    pub demoted_properties: Vec<DemotedProperty>,
    pub contract_ref: Option<String>,
    pub max_bytes_to_inspect: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ContentOperation {
    Identify,
    Inspect,
    CreateMessageSections,
    Promote,
    Demote,
    Validate,
    Serialize,
    Materialize,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContentPropertySelector {
    pub property_name: String,
    pub selector: ContentSelector,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContentSelector {
    pub expression: String,
    pub segments: Vec<ContentSelectorSegment>,
    pub evaluation: SelectorEvaluation,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ContentSelectorSegment {
    Name(String),
    Number(u64),
    Key(String),
    Any,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum SelectorEvaluation {
    StreamPrefix,
    StreamScan,
    MaterializedSection,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PromotedProperty {
    pub name: String,
    pub value: String,
    pub source: ContentPropertySelector,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct DemotedProperty {
    pub name: String,
    pub value: String,
    pub source: Option<ContentPropertySelector>,
    pub target: DemotionTarget,
    pub target_selector: Option<ContentSelector>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum DemotionTarget {
    StreamHeader,
    StreamMetadata,
    PayloadElement,
    Envelope,
    TransportProperty,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContentHandlerResult {
    pub invocation_id: Uuid,
    pub status: HandlerStatus,
    pub recognized: Option<bool>,
    pub message_sections: Vec<ContentMessageSection>,
    pub promoted_properties: Vec<PromotedProperty>,
    pub demoted_properties: Vec<DemotedProperty>,
    pub output_payload_ref: Option<String>,
    pub diagnostic: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContentMessageSection {
    pub section_name: Option<String>,
    pub stream_ref: String,
    pub content_type: Option<String>,
}

pub trait XmipModule: Send + Sync {
    fn manifest(&self) -> &ModuleManifest;
}

pub trait TransportHandler: XmipModule {
    fn receive(&self, invocation: HandlerInvocation) -> HandlerResult;
    fn send(&self, invocation: HandlerInvocation) -> HandlerResult;
}

pub trait ContentHandler: XmipModule {
    fn handle_content(&self, invocation: ContentHandlerInvocation) -> ContentHandlerResult;
}
