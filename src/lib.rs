//! What has not yet moved to the repository that owns it.
//!
//! transport, transport_technology and disposition left on 2026-08-26 —
//! `docs/planning/allocation.toml` records where each went. contracts, route
//! and journey_model are `[[merge]]` entries: the destination repository has
//! its own implementation, and reconciling the two is a judgement per file
//! rather than a move.
//!
//! When those three are merged this file becomes the assembly, re-exporting
//! the module crates so `xmip` stays one import for anyone who wants the whole
//! platform.

pub mod contracts;
pub mod journey_model;
pub mod route;
pub mod vertical_slice;

pub use contracts::{
    ContentCreatedMessage, ContentHandler, ContentHandlerInvocation, ContentHandlerResult,
    ContentOperation, ContentPropertySelector, ContentSelector, ContentSelectorSegment,
    DemotedProperty, DemotionTarget, ExecutionHostKind, ExtensionEntrypoint, ExtensionManifest,
    HandlerInvocation, HandlerResult, HandlerStatus, Module, ModuleCapability, ModuleEntrypoint,
    ModuleIdentity, ModuleKind, ModuleManifest, PromotedProperty, SelectorEvaluation,
    TransportHandler, XmipModule,
};

pub use journey_model::{
    append_message_to_journey, create_derived_message, create_initial_message,
    create_initial_message_with_treatment, create_metadata_only_message, ExecutionProfile, Journey,
    JourneyMessageRef, JourneyState, Message, MessageCreationSource, MessageDurability,
    MessagePriority, MessageTreatment, StreamRef,
};

pub use route::{
    never_satisfiable, publish, Dispatch, Evaluation, NeverFires, Predicate, Promoted, Routing,
    Subscription, Test, Value,
};

