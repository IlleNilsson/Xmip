use xmip_module_api::ModuleManifest;
use xmip_runtime::{HostBitness, HostProcessPlan};

#[derive(Clone, Debug)]
pub struct HostProcess {
    pub plan: HostProcessPlan,
    pub state: HostProcessState,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HostProcessState {
    Planned,
    Starting,
    Running,
    Stopped,
    Failed(String),
}

impl HostProcess {
    pub fn from_manifest(manifest: ModuleManifest, trusted: bool, low_latency: bool) -> Self {
        Self {
            plan: HostProcessPlan {
                host_type: format!("{}-host", manifest.identity.name),
                trusted,
                bitness: HostBitness::Native,
                low_latency,
                modules: vec![manifest],
                verified_extensions: Vec::new(),
            },
            state: HostProcessState::Planned,
        }
    }

    pub fn start(&mut self) {
        self.state = HostProcessState::Starting;
        self.state = HostProcessState::Running;
    }

    pub fn stop(&mut self) {
        self.state = HostProcessState::Stopped;
    }
}

#[cfg(feature = "dynamic-loading")]
pub mod dynamic {
    use xmip_module_api::ModuleManifest;

    #[derive(Clone, Debug)]
    pub struct DynamicModuleRequest {
        pub manifest: ModuleManifest,
        pub resolved_library_path: String,
    }

    pub fn validate_dynamic_request(request: &DynamicModuleRequest) -> Result<(), String> {
        if request.resolved_library_path.trim().is_empty() {
            return Err("dynamic module request requires a resolved library path".to_string());
        }

        if request.manifest.entrypoint.symbol.as_deref().unwrap_or_default().is_empty() {
            return Err("dynamic module request requires an exported symbol".to_string());
        }

        Ok(())
    }
}
