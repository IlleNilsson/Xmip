use crate::handler::{HandlerDescriptor, HandlerKind};
use crate::handler_registry::{HandlerRegistry, RegisteredHandler};
use crate::module_manifest::{XmipModuleKind, XmipModuleManifest};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct ModuleLoaderConfig {
    pub module_roots: Vec<PathBuf>,
}

#[derive(Debug, Clone)]
pub struct LoadedModule {
    pub manifest: XmipModuleManifest,
    pub manifest_path: PathBuf,
}

pub struct ModuleLoader {
    config: ModuleLoaderConfig,
}

impl ModuleLoader {
    pub fn new(config: ModuleLoaderConfig) -> Self {
        Self { config }
    }

    pub fn discover_manifest_paths(&self) -> io::Result<Vec<PathBuf>> {
        let mut manifests = Vec::new();

        for root in &self.config.module_roots {
            discover_manifest_paths(root, &mut manifests)?;
        }

        Ok(manifests)
    }

    pub fn register_manifest(&self, registry: &mut HandlerRegistry, manifest: XmipModuleManifest) {
        let kind = match manifest.kind {
            XmipModuleKind::ReceiveTechnology => HandlerKind::Receive,
            XmipModuleKind::SendLocationTechnology => HandlerKind::Send,
            XmipModuleKind::ContentHandler => HandlerKind::Content,
            XmipModuleKind::LogicHandler => HandlerKind::Logic,
            _ => return,
        };

        for technology in &manifest.supported_technologies {
            registry.register(RegisteredHandler {
                descriptor: HandlerDescriptor {
                    name: technology.clone(),
                    kind: kind.clone(),
                    module_name: manifest.component_id.clone(),
                },
                module_component_id: manifest.component_id.clone(),
                binary_path: manifest.binary_path.clone(),
            });
        }
    }
}

fn discover_manifest_paths(root: &Path, manifests: &mut Vec<PathBuf>) -> io::Result<()> {
    if !root.exists() {
        return Ok(());
    }

    for item in fs::read_dir(root)? {
        let item = item?;
        let path = item.path();

        if path.is_dir() {
            discover_manifest_paths(&path, manifests)?;
        } else if path
            .file_name()
            .map(|name| name == "xmip-module.toml")
            .unwrap_or(false)
        {
            manifests.push(path);
        }
    }

    Ok(())
}
