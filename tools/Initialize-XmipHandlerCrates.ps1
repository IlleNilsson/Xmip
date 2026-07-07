param(
    [string]$Root = "."
)

$ErrorActionPreference = "Stop"

$handlers = @(
    @{ Name = "Xmip.Handler.File"; Capability = "transport:file"; Kind = "file"; Path = "modules/file-system/Xmip.Handler.File"; LowLatency = "false"; Trusted = "true" },
    @{ Name = "Xmip.Handler.FileWatch"; Capability = "transport:file-watch"; Kind = "file-watch"; Path = "modules/file-system/file-watch/Xmip.Handler.FileWatch"; LowLatency = "false"; Trusted = "true" },
    @{ Name = "Xmip.Handler.FilePoll"; Capability = "transport:file-poll"; Kind = "file-poll"; Path = "modules/file-system/file-poll/Xmip.Handler.FilePoll"; LowLatency = "false"; Trusted = "true" },

    @{ Name = "Xmip.Handler.Tcp"; Capability = "transport:tcp"; Kind = "tcp"; Path = "modules/ip/tcp/Xmip.Handler.Tcp"; LowLatency = "true"; Trusted = "true" },
    @{ Name = "Xmip.Handler.Http"; Capability = "transport:http"; Kind = "http"; Path = "modules/ip/tcp/http/Xmip.Handler.Http"; LowLatency = "true"; Trusted = "true" },
    @{ Name = "Xmip.Handler.Soap"; Capability = "transport:soap"; Kind = "soap"; Path = "modules/ip/tcp/http/Xmip.Handler.Soap"; LowLatency = "false"; Trusted = "true" },
    @{ Name = "Xmip.Handler.Rest"; Capability = "transport:rest"; Kind = "rest"; Path = "modules/ip/tcp/http/Xmip.Handler.Rest"; LowLatency = "true"; Trusted = "true" },
    @{ Name = "Xmip.Handler.Webhook"; Capability = "transport:webhook"; Kind = "webhook"; Path = "modules/ip/tcp/http/Xmip.Handler.Webhook"; LowLatency = "true"; Trusted = "true" },
    @{ Name = "Xmip.Handler.Grpc"; Capability = "transport:grpc"; Kind = "grpc"; Path = "modules/ip/tcp/http/grpc/Xmip.Handler.Grpc"; LowLatency = "true"; Trusted = "true" },

    @{ Name = "Xmip.Handler.Ftp"; Capability = "transport:ftp"; Kind = "ftp"; Path = "modules/ip/tcp/ftp/Xmip.Handler.Ftp"; LowLatency = "false"; Trusted = "true" },
    @{ Name = "Xmip.Handler.Sftp"; Capability = "transport:sftp"; Kind = "sftp"; Path = "modules/ip/tcp/ftp/Xmip.Handler.Sftp"; LowLatency = "false"; Trusted = "true" },
    @{ Name = "Xmip.Handler.Mllp"; Capability = "transport:mllp"; Kind = "mllp"; Path = "modules/ip/tcp/mllp/Xmip.Handler.Mllp"; LowLatency = "true"; Trusted = "true" },
    @{ Name = "Xmip.Handler.Mqtt"; Capability = "transport:mqtt"; Kind = "mqtt"; Path = "modules/ip/tcp/mqtt/Xmip.Handler.Mqtt"; LowLatency = "true"; Trusted = "true" },

    @{ Name = "Xmip.Handler.Udp"; Capability = "transport:udp"; Kind = "udp"; Path = "modules/ip/udp/Xmip.Handler.Udp"; LowLatency = "true"; Trusted = "true" },
    @{ Name = "Xmip.Handler.Dns"; Capability = "transport:dns"; Kind = "dns"; Path = "modules/ip/udp/dns/Xmip.Handler.Dns"; LowLatency = "true"; Trusted = "true" },
    @{ Name = "Xmip.Handler.Syslog"; Capability = "transport:syslog"; Kind = "syslog"; Path = "modules/ip/udp/syslog/Xmip.Handler.Syslog"; LowLatency = "true"; Trusted = "true" }
)

function Convert-ToCrateName {
    param([string]$Name)
    return $Name.ToLowerInvariant().Replace(".", "-")
}

function Convert-ToRustTypeName {
    param([string]$Name)
    $parts = $Name.Split(".")
    return ($parts | ForEach-Object { $_.Substring(0,1).ToUpperInvariant() + $_.Substring(1) }) -join ""
}

foreach ($handler in $handlers) {
    $target = Join-Path $Root $handler.Path
    $src = Join-Path $target "src"
    New-Item -ItemType Directory -Force $src | Out-Null

    $crateName = Convert-ToCrateName $handler.Name
    $typeName = Convert-ToRustTypeName $handler.Name
    $kind = $handler.Kind
    $capability = $handler.Capability
    $lowLatency = $handler.LowLatency
    $trusted = $handler.Trusted

    @"
[package]
name = "$crateName"
version = "0.1.0"
edition = "2021"
license = "LicenseRef-Xmip-Free-Use-No-Fork"

[lib]
crate-type = ["rlib", "cdylib"]

[dependencies]
xmip-core = { path = "../../../../.." }
xmip-abi = { path = "../../../../../crates/xmip-module-abi" }
"@ | Set-Content (Join-Path $target "Cargo.toml") -Encoding UTF8

    @"
use xmip_abi::{ModuleAbiDescriptor, ModuleAbiKind, XMIP_MODULE_ABI_VERSION};
use xmip_core::{
    ExecutionHostKind, HandlerInvocation, HandlerResult, HandlerStatus, ModuleCapability,
    ModuleEntrypoint, ModuleIdentity, ModuleKind, ModuleManifest, TransportHandler, XmipModule,
};

pub struct $typeName {
    manifest: ModuleManifest,
}

impl Default for $typeName {
    fn default() -> Self {
        Self {
            manifest: ModuleManifest {
                identity: ModuleIdentity {
                    name: "$($handler.Name)".to_string(),
                    version: env!("CARGO_PKG_VERSION").to_string(),
                    kind: ModuleKind::TransportHandler,
                },
                capabilities: vec![ModuleCapability {
                    capability: "$capability".to_string(),
                    execution_host: ExecutionHostKind::NativeRust,
                    low_latency_capable: $lowLatency,
                    trusted_required: $trusted,
                }],
                entrypoint: ModuleEntrypoint {
                    library_path: Some("$crateName".to_string()),
                    executable_path: None,
                    symbol: Some("xmip_create_module_v1".to_string()),
                },
            },
        }
    }
}

impl XmipModule for $typeName {
    fn manifest(&self) -> &ModuleManifest {
        &self.manifest
    }
}

impl TransportHandler for $typeName {
    fn receive(&self, invocation: HandlerInvocation) -> HandlerResult {
        HandlerResult {
            invocation_id: invocation.invocation_id,
            status: HandlerStatus::Completed,
            output_payload_ref: Some(invocation.payload_ref),
            promoted_properties: vec![("xmip.transport".to_string(), "$kind".to_string())],
            diagnostic: Some("scaffold receive completed; protocol-specific implementation pending".to_string()),
        }
    }

    fn send(&self, invocation: HandlerInvocation) -> HandlerResult {
        HandlerResult {
            invocation_id: invocation.invocation_id,
            status: HandlerStatus::Completed,
            output_payload_ref: Some(invocation.payload_ref),
            promoted_properties: vec![("xmip.transport".to_string(), "$kind".to_string())],
            diagnostic: Some("scaffold send completed; protocol-specific implementation pending".to_string()),
        }
    }
}

#[no_mangle]
pub extern "C" fn xmip_module_descriptor_v1() -> ModuleAbiDescriptor {
    ModuleAbiDescriptor {
        abi_version: XMIP_MODULE_ABI_VERSION,
        module_kind: ModuleAbiKind::TransportHandler,
    }
}

#[no_mangle]
pub extern "C" fn xmip_create_module_v1() -> *mut $typeName {
    Box::into_raw(Box::new($typeName::default()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_declares_transport_capability() {
        let handler = $typeName::default();
        assert_eq!(handler.manifest().identity.name, "$($handler.Name)");
        assert_eq!(handler.manifest().capabilities[0].capability, "$capability");
    }
}
"@ | Set-Content (Join-Path $src "lib.rs") -Encoding UTF8

    @"
# $($handler.Name)

Rust Xmip Transport Handler scaffold.

Technology kind: `$kind`
Capability: `$capability`

This crate is intentionally buildable before the full protocol implementation is added.
"@ | Set-Content (Join-Path $target "README.md") -Encoding UTF8
}

Write-Host "Generated Xmip handler crate scaffolds."
