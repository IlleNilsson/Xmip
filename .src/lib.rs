//! Xmip, assembled.
//!
//! This crate holds no behavior. Every module is its own repository, and this
//! re-exports them so `xmip` stays one import for anyone who wants the whole
//! platform rather than one capability. What used to live here went to the
//! repositories that own it on 2026-08-26; `doc/planning/allocation.toml` is
//! the ledger of where each part went and why.
//!
//! The re-exports below the fold are behind features and a build profile
//! selects a set of them. The ones above are always present: without them
//! there is nothing to configure.

pub use xmip_abi;
pub use xmip_configure;
pub use xmip_context;
pub use xmip_core;
pub use xmip_journey;
pub use xmip_message;
pub use xmip_receive;
pub use xmip_route;
pub use xmip_runtime;
pub use xmip_send;
pub use xmip_stream;
pub use xmip_transport;

#[cfg(feature = "archive")]
pub use xmip_archive;
#[cfg(feature = "assign")]
pub use xmip_assign;
#[cfg(feature = "audit")]
pub use xmip_audit;
#[cfg(feature = "authenticate")]
pub use xmip_authenticate;
#[cfg(feature = "authorize")]
pub use xmip_authorize;
#[cfg(feature = "cluster")]
pub use xmip_cluster;
#[cfg(feature = "contract")]
pub use xmip_contract;
#[cfg(feature = "demote")]
pub use xmip_demote;
#[cfg(feature = "event")]
pub use xmip_event;
#[cfg(feature = "identify")]
pub use xmip_identify;
#[cfg(feature = "node")]
pub use xmip_node;
#[cfg(feature = "observe")]
pub use xmip_observe;
#[cfg(feature = "party")]
pub use xmip_party;
#[cfg(feature = "path")]
pub use xmip_path;
#[cfg(feature = "persist")]
pub use xmip_persist;
#[cfg(feature = "prepare")]
pub use xmip_prepare;
#[cfg(feature = "process")]
pub use xmip_process;
#[cfg(feature = "promote")]
pub use xmip_promote;
#[cfg(feature = "report")]
pub use xmip_report;
#[cfg(feature = "resilience")]
pub use xmip_resilience;
#[cfg(feature = "retain")]
pub use xmip_retain;
#[cfg(feature = "transform")]
pub use xmip_transform;
