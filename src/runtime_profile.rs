#[derive(Debug, Clone, PartialEq, Eq)]
pub enum XmipRuntimeProfile {
    ServerDynamic,
    PurposeCompiled,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum XmipDeploymentSide {
    ServerSide,
    EndpointSide,
    SmallDevice,
    IndustrialGateway,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmipRuntimePackaging {
    pub profile: XmipRuntimeProfile,
    pub side: XmipDeploymentSide,
    pub dynamic_modules_enabled: bool,
    pub compiled_capabilities: Vec<String>,
}

impl XmipRuntimePackaging {
    pub fn server_dynamic() -> Self {
        Self {
            profile: XmipRuntimeProfile::ServerDynamic,
            side: XmipDeploymentSide::ServerSide,
            dynamic_modules_enabled: true,
            compiled_capabilities: Vec::new(),
        }
    }

    pub fn purpose_compiled(side: XmipDeploymentSide, capabilities: Vec<String>) -> Self {
        Self {
            profile: XmipRuntimeProfile::PurposeCompiled,
            side,
            dynamic_modules_enabled: false,
            compiled_capabilities: capabilities,
        }
    }
}
