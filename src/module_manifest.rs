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
pub enum CommunicationMedium {
    IpNetwork,
    CanNetwork,
    Serial,
    WirelessIot,
    FileSystem,
    BrokerOrCloudService,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TransportLayer {
    Tcp,
    Udp,
    CanBus,
    Rs232,
    Rs485,
    None,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommunicationLayering {
    pub medium: CommunicationMedium,
    pub transport: TransportLayer,
    pub protocol: String,
    pub interaction_patterns: Vec<String>,
    pub capabilities: Vec<String>,
}

impl CommunicationLayering {
    pub fn canbus() -> Self {
        Self {
            medium: CommunicationMedium::CanNetwork,
            transport: TransportLayer::CanBus,
            protocol: "canbus".to_string(),
            interaction_patterns: vec!["frame".to_string()],
            capabilities: vec!["receive".to_string(), "send".to_string()],
        }
    }

    pub fn http() -> Self {
        Self {
            medium: CommunicationMedium::IpNetwork,
            transport: TransportLayer::Tcp,
            protocol: "http".to_string(),
            interaction_patterns: vec!["request-response".to_string()],
            capabilities: vec!["receive".to_string(), "send".to_string()],
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmipHandlerLineage {
    pub family: String,
    pub base_component_id: Option<String>,
    pub derives_from: Vec<String>,
}

impl XmipHandlerLineage {
    pub fn root(family: &str) -> Self {
        Self {
            family: family.to_string(),
            base_component_id: None,
            derives_from: Vec::new(),
        }
    }

    pub fn derived(family: &str, base_component_id: &str, derives_from: Vec<String>) -> Self {
        Self {
            family: family.to_string(),
            base_component_id: Some(base_component_id.to_string()),
            derives_from,
        }
    }
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
    pub lineage: XmipHandlerLineage,
    pub layering: CommunicationLayering,
    pub supported_technologies: Vec<String>,
}

impl XmipModuleManifest {
    pub fn is_loadable_on(&self, platform: XmipModulePlatform) -> bool {
        self.platform == XmipModulePlatform::Any || self.platform == platform
    }

    pub fn is_in_family(&self, family: &str) -> bool {
        self.lineage.family == family
    }

    pub fn derives_from_component(&self, component_id: &str) -> bool {
        self.lineage.base_component_id.as_deref() == Some(component_id)
            || self.lineage.derives_from.iter().any(|item| item == component_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sftp_can_declare_ftp_lineage() {
        let manifest = XmipModuleManifest {
            component_id: "xmip.receive.sftp".to_string(),
            kind: XmipModuleKind::ReceiveTechnology,
            version: "0.1.0".to_string(),
            xmip_contract_version: "0.1.0".to_string(),
            platform: XmipModulePlatform::Any,
            binary_path: "xmip.receive.sftp.dll".to_string(),
            isolation: XmipModuleIsolation::TrustedHost,
            lineage: XmipHandlerLineage::derived(
                "ftp-family",
                "xmip.receive.ftp",
                vec!["xmip.receive.ftp".to_string()],
            ),
            layering: CommunicationLayering {
                medium: CommunicationMedium::IpNetwork,
                transport: TransportLayer::Tcp,
                protocol: "sftp".to_string(),
                interaction_patterns: vec!["remote-file".to_string(), "polling".to_string()],
                capabilities: vec!["receive".to_string(), "send".to_string()],
            },
            supported_technologies: vec!["sftp".to_string()],
        };

        assert!(manifest.is_in_family("ftp-family"));
        assert!(manifest.derives_from_component("xmip.receive.ftp"));
    }

    #[test]
    fn canbus_is_not_tcp_or_udp() {
        let layering = CommunicationLayering::canbus();

        assert_eq!(layering.medium, CommunicationMedium::CanNetwork);
        assert_eq!(layering.transport, TransportLayer::CanBus);
        assert_ne!(layering.transport, TransportLayer::Tcp);
        assert_ne!(layering.transport, TransportLayer::Udp);
    }

    #[test]
    fn http_is_ip_over_tcp() {
        let layering = CommunicationLayering::http();

        assert_eq!(layering.medium, CommunicationMedium::IpNetwork);
        assert_eq!(layering.transport, TransportLayer::Tcp);
        assert_eq!(layering.protocol, "http");
    }
}
