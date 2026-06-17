use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct ModuleManifestToml {
    pub component_id: String,
    pub kind: String,
    pub version: String,
    pub xmip_contract_version: String,
    pub platform: String,
    pub binary_path: String,
    pub isolation: String,
    pub family: String,
    pub base_component_id: Option<String>,
    pub derives_from: Option<Vec<String>>,
    pub medium: String,
    pub transport: String,
    pub protocol: String,
    pub interaction_patterns: Option<Vec<String>>,
    pub capabilities: Option<Vec<String>>,
    pub supported_technologies: Vec<String>,
}
