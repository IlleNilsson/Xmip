#[derive(Debug, Clone, PartialEq, Eq)]
pub enum XmipModuleKind {
    ReceiveTechnology,
    SendLocationTechnology,
    ContentHandler,
    LogicHandler,
    Transformation,
    ProcessHandler,
    Extension,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum XmipModulePlatform {
    Windows,
    Linux,
    MacOs,
    Any,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum XmipModuleIsolation {
    InProcess,
    OutOfProcess,
    TrustedHost,
    UntrustedHost,
    LowLatencyHost,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmipModuleManifest {
    pub component_id: String,
    pub kind: XmipModuleKind,
    pub version: String,
    pub xmip_contract_version: String,
    pub platform: XmipModulePlatform,
    pub binary_path: String,
    pub isolation: XmipModuleIsolation,
    pub supported_technologies: Vec<String>,
}

impl XmipModuleManifest {
    pub fn is_loadable_on(&self, platform: XmipModulePlatform) -> bool {
        self.platform == XmipModulePlatform::Any || self.platform == platform
    }
}
