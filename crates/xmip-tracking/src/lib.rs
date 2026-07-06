use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TrackingEvent {
    pub event_id: Uuid,
    pub cluster_name: String,
    pub node_name: String,
    pub journey_id: Option<Uuid>,
    pub message_id: Option<Uuid>,
    pub action: TrackingAction,
    pub artifact_name: Option<String>,
    pub detail: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum TrackingAction {
    StartupValidation,
    ModuleLoaded,
    ExtensionVerified,
    EventObserved,
    JourneyStarted,
    JourneyWaiting,
    JourneyResumed,
    JourneyCompleted,
    Receive,
    XmipProcess,
    Assignment,
    Transformation,
    Send,
    Fault,
}

pub trait TrackingSink {
    fn record(&self, event: TrackingEvent) -> Result<(), String>;
}

pub fn startup_validation_event(
    cluster_name: impl Into<String>,
    node_name: impl Into<String>,
    detail: impl Into<String>,
) -> TrackingEvent {
    TrackingEvent {
        event_id: Uuid::new_v4(),
        cluster_name: cluster_name.into(),
        node_name: node_name.into(),
        journey_id: None,
        message_id: None,
        action: TrackingAction::StartupValidation,
        artifact_name: None,
        detail: detail.into(),
    }
}

pub fn journey_event(
    cluster_name: impl Into<String>,
    node_name: impl Into<String>,
    journey_id: Uuid,
    message_id: Option<Uuid>,
    action: TrackingAction,
    detail: impl Into<String>,
) -> TrackingEvent {
    TrackingEvent {
        event_id: Uuid::new_v4(),
        cluster_name: cluster_name.into(),
        node_name: node_name.into(),
        journey_id: Some(journey_id),
        message_id,
        action,
        artifact_name: None,
        detail: detail.into(),
    }
}
