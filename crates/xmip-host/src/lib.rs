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
    use xmip_module_api::{
        validate_module_abi, ModuleAbiDescriptor, ModuleManifest, XMIP_MODULE_ENTRYPOINT,
    };

    #[derive(Clone, Debug)]
    pub struct DynamicModuleRequest {
        pub manifest: ModuleManifest,
        pub resolved_library_path: String,
        pub descriptor: ModuleAbiDescriptor,
    }

    #[derive(Clone, Debug, PartialEq, Eq)]
    pub struct VerifiedDynamicModule {
        pub module_name: String,
        pub resolved_library_path: String,
        pub entrypoint_symbol: String,
    }

    pub fn verify_dynamic_module(
        request: &DynamicModuleRequest,
    ) -> Result<VerifiedDynamicModule, String> {
        if request.resolved_library_path.trim().is_empty() {
            return Err("dynamic module request requires a resolved library path".to_string());
        }

        validate_module_abi(request.descriptor)?;

        let entrypoint_symbol = request
            .manifest
            .entrypoint
            .symbol
            .clone()
            .unwrap_or_else(|| XMIP_MODULE_ENTRYPOINT.to_string());

        if entrypoint_symbol.trim().is_empty() {
            return Err("dynamic module request requires an exported symbol".to_string());
        }

        Ok(VerifiedDynamicModule {
            module_name: request.manifest.identity.name.clone(),
            resolved_library_path: request.resolved_library_path.clone(),
            entrypoint_symbol,
        })
    }
}
