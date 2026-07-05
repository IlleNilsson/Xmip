pub const XMIP_MODULE_ABI_VERSION: u32 = 1;
pub const XMIP_MODULE_ENTRYPOINT: &str = "xmip_create_module_v1";

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ModuleAbiDescriptor {
    pub abi_version: u32,
    pub module_kind: ModuleAbiKind,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ModuleAbiKind {
    TransportHandler = 1,
    ContentHandler = 2,
    LogicHandler = 3,
    StoreProvider = 4,
    ManagementModule = 5,
}

pub fn validate_module_abi(descriptor: ModuleAbiDescriptor) -> Result<(), String> {
    if descriptor.abi_version != XMIP_MODULE_ABI_VERSION {
        return Err(format!(
            "unsupported module ABI version {}; expected {}",
            descriptor.abi_version, XMIP_MODULE_ABI_VERSION
        ));
    }

    Ok(())
}
