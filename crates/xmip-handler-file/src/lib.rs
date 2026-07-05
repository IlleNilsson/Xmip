use xmip_plugin_api::{
    ExecutionHostKind, HandlerInvocation, HandlerResult, HandlerStatus, ModuleCapability,
    ModuleEntrypoint, ModuleIdentity, ModuleKind, ModuleManifest, TransportHandler, XmipModule,
};

pub struct FileTransportHandler {
    manifest: ModuleManifest,
}

impl Default for FileTransportHandler {
    fn default() -> Self {
        Self {
            manifest: ModuleManifest {
                identity: ModuleIdentity {
                    name: "xmip-handler-file".to_string(),
                    version: env!("CARGO_PKG_VERSION").to_string(),
                    kind: ModuleKind::TransportHandler,
                },
                capabilities: vec![ModuleCapability {
                    capability: "transport:file".to_string(),
                    execution_host: ExecutionHostKind::NativeRust,
                    low_latency_capable: false,
                    trusted_required: true,
                }],
                entrypoint: ModuleEntrypoint {
                    library_path: Some("xmip_handler_file".to_string()),
                    executable_path: None,
                    symbol: Some("xmip_create_module".to_string()),
                },
            },
        }
    }
}

impl XmipModule for FileTransportHandler {
    fn manifest(&self) -> &ModuleManifest {
        &self.manifest
    }
}

impl TransportHandler for FileTransportHandler {
    fn receive(&self, invocation: HandlerInvocation) -> HandlerResult {
        HandlerResult {
            invocation_id: invocation.invocation_id,
            status: HandlerStatus::Completed,
            output_payload_ref: Some(invocation.payload_ref),
            promoted_properties: vec![("xmip.transport".to_string(), "file".to_string())],
            diagnostic: None,
        }
    }

    fn send(&self, invocation: HandlerInvocation) -> HandlerResult {
        HandlerResult {
            invocation_id: invocation.invocation_id,
            status: HandlerStatus::Completed,
            output_payload_ref: Some(invocation.payload_ref),
            promoted_properties: Vec::new(),
            diagnostic: None,
        }
    }
}

#[no_mangle]
pub extern "C" fn xmip_create_module() -> *mut FileTransportHandler {
    Box::into_raw(Box::new(FileTransportHandler::default()))
}
