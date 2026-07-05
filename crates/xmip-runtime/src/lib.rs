use serde::{Deserialize, Serialize};
use xmip_plugin_api::{HandlerInvocation, HandlerResult, PluginManifest};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuntimeNode {
    pub cluster_name: String,
    pub node_name: String,
    pub roles: Vec<NodeRole>,
    pub host_processes: Vec<HostProcessPlan>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum NodeRole {
    Operational,
    Monitoring,
    Executing,
    Development,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct HostProcessPlan {
    pub host_type: String,
    pub trusted: bool,
    pub bitness: HostBitness,
    pub low_latency: bool,
    pub modules: Vec<PluginManifest>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum HostBitness {
    Bit32,
    Bit64,
    Native,
}

#[derive(Clone, Debug, Default)]
pub struct ModuleRegistry {
    manifests: Vec<PluginManifest>,
}

impl ModuleRegistry {
    pub fn register(&mut self, manifest: PluginManifest) {
        self.manifests.push(manifest);
    }

    pub fn manifests(&self) -> &[PluginManifest] {
        &self.manifests
    }

    pub fn plan_host_processes(&self, cluster_name: &str, node_name: &str) -> RuntimeNode {
        RuntimeNode {
            cluster_name: cluster_name.to_string(),
            node_name: node_name.to_string(),
            roles: vec![NodeRole::Operational, NodeRole::Executing],
            host_processes: self
                .manifests
                .iter()
                .cloned()
                .map(|module| HostProcessPlan {
                    host_type: format!("{}-host", module.identity.kind_name()),
                    trusted: module.capabilities.iter().any(|c| c.trusted_required),
                    bitness: HostBitness::Native,
                    low_latency: module.capabilities.iter().any(|c| c.low_latency_capable),
                    modules: vec![module],
                })
                .collect(),
        }
    }
}

pub trait RuntimeDispatcher {
    fn dispatch(&self, invocation: HandlerInvocation) -> HandlerResult;
}

trait PluginKindName {
    fn kind_name(&self) -> &'static str;
}

impl PluginKindName for xmip_plugin_api::PluginKind {
    fn kind_name(&self) -> &'static str {
        match self {
            xmip_plugin_api::PluginKind::TransportHandler => "transport",
            xmip_plugin_api::PluginKind::ContentHandler => "content",
            xmip_plugin_api::PluginKind::LogicHandler => "logic",
            xmip_plugin_api::PluginKind::StoreProvider => "store",
            xmip_plugin_api::PluginKind::ManagementExtension => "management",
        }
    }
}
