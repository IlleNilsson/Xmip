use serde::{Deserialize, Serialize};
use xmip_module_api::{ExtensionManifest, ModuleManifest};
use xmip_runtime::execution_tree::{
    ConfiguredModule, ConfiguredXmipProcess, ConfiguredXmipSubprocess, XmipServiceConfiguration,
};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct XmipConfigurationDocument {
    pub service: ServiceConfiguration,
    pub modules: Vec<ModuleConfiguration>,
    pub xmip_processes: Vec<XmipProcessConfiguration>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServiceConfiguration {
    pub name: String,
    pub cluster_name: String,
    pub node_name: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleConfiguration {
    pub name: String,
    pub start: bool,
    pub manifest: ModuleManifest,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct XmipProcessConfiguration {
    pub name: String,
    pub start: bool,
    pub required_modules: Vec<String>,
    pub subprocesses: Vec<XmipSubprocessConfiguration>,
    pub extensions: Vec<ExtensionManifest>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct XmipSubprocessConfiguration {
    pub name: String,
    pub required_modules: Vec<String>,
    pub extensions: Vec<ExtensionManifest>,
}

pub fn parse_toml(source: &str) -> Result<XmipConfigurationDocument, String> {
    toml::from_str(source).map_err(|error| error.to_string())
}

pub fn to_service_configuration(document: XmipConfigurationDocument) -> XmipServiceConfiguration {
    XmipServiceConfiguration {
        service_name: document.service.name,
        cluster_name: document.service.cluster_name,
        node_name: document.service.node_name,
        modules: document
            .modules
            .into_iter()
            .map(|module| ConfiguredModule {
                name: module.name,
                manifest: module.manifest,
                start: module.start,
            })
            .collect(),
        xmip_processes: document
            .xmip_processes
            .into_iter()
            .map(|xmip_process| ConfiguredXmipProcess {
                name: xmip_process.name,
                start: xmip_process.start,
                required_modules: xmip_process.required_modules,
                subprocesses: xmip_process
                    .subprocesses
                    .into_iter()
                    .map(|subprocess| ConfiguredXmipSubprocess {
                        name: subprocess.name,
                        required_modules: subprocess.required_modules,
                        extensions: subprocess.extensions,
                    })
                    .collect(),
                extensions: xmip_process.extensions,
            })
            .collect(),
    }
}

pub fn parse_service_configuration(source: &str) -> Result<XmipServiceConfiguration, String> {
    parse_toml(source).map(to_service_configuration)
}
