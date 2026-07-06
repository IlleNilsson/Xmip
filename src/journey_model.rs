use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Journey {
    pub journey_id: Uuid,
    pub state: JourneyState,
    pub current_xmip_process: Option<String>,
    pub messages: Vec<JourneyMessageRef>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum JourneyState {
    Active,
    Waiting,
    Suspended,
    Recovering,
    Completed,
    Failed,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct JourneyMessageRef {
    pub message_id: Uuid,
    pub stream_id: Uuid,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Message {
    pub journey_id: Uuid,
    pub message_id: Uuid,
    pub stream_ref: StreamRef,
    pub generation: u32,
    pub created_by: MessageCreationSource,
    pub priority: MessagePriority,
    pub execution_profile: ExecutionProfile,
    pub durability: MessageDurability,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StreamRef {
    pub stream_id: Uuid,
    pub uri: String,
    pub immutable: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum MessageCreationSource {
    Receive,
    Assignment,
    Transformation,
    SendPreparation,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum MessagePriority {
    Immediate,
    High,
    Normal,
    Low,
    Background,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum ExecutionProfile {
    Conversation,
    Business,
    PassThrough,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum MessageDurability {
    Ephemeral,
    Durable,
    Recoverable,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageTreatment {
    pub priority: MessagePriority,
    pub execution_profile: ExecutionProfile,
    pub durability: MessageDurability,
}

impl Default for MessageTreatment {
    fn default() -> Self {
        Self {
            priority: MessagePriority::Normal,
            execution_profile: ExecutionProfile::Business,
            durability: MessageDurability::Recoverable,
        }
    }
}

pub fn create_initial_message(stream_uri: impl Into<String>) -> (Journey, Message) {
    create_initial_message_with_treatment(stream_uri, MessageTreatment::default())
}

pub fn create_initial_message_with_treatment(
    stream_uri: impl Into<String>,
    treatment: MessageTreatment,
) -> (Journey, Message) {
    let journey_id = Uuid::new_v4();
    let message_id = Uuid::new_v4();
    let stream_id = Uuid::new_v4();

    let message = Message {
        journey_id,
        message_id,
        stream_ref: StreamRef {
            stream_id,
            uri: stream_uri.into(),
            immutable: true,
        },
        generation: 0,
        created_by: MessageCreationSource::Receive,
        priority: treatment.priority,
        execution_profile: treatment.execution_profile,
        durability: treatment.durability,
    };

    let journey = Journey {
        journey_id,
        state: JourneyState::Active,
        current_xmip_process: None,
        messages: vec![JourneyMessageRef {
            message_id,
            stream_id,
        }],
    };

    (journey, message)
}

pub fn create_derived_message(
    previous: &Message,
    stream_uri: impl Into<String>,
    created_by: MessageCreationSource,
) -> Message {
    Message {
        journey_id: previous.journey_id,
        message_id: Uuid::new_v4(),
        stream_ref: StreamRef {
            stream_id: Uuid::new_v4(),
            uri: stream_uri.into(),
            immutable: true,
        },
        generation: previous.generation + 1,
        created_by,
        priority: previous.priority.clone(),
        execution_profile: previous.execution_profile.clone(),
        durability: previous.durability.clone(),
    }
}

pub fn create_metadata_only_message(
    previous: &Message,
    created_by: MessageCreationSource,
) -> Message {
    Message {
        journey_id: previous.journey_id,
        message_id: Uuid::new_v4(),
        stream_ref: previous.stream_ref.clone(),
        generation: previous.generation + 1,
        created_by,
        priority: previous.priority.clone(),
        execution_profile: previous.execution_profile.clone(),
        durability: previous.durability.clone(),
    }
}

pub fn append_message_to_journey(journey: &mut Journey, message: &Message) {
    if journey.journey_id != message.journey_id {
        return;
    }

    journey.messages.push(JourneyMessageRef {
        message_id: message.message_id,
        stream_id: message.stream_ref.stream_id,
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn assignment_can_create_new_message_with_same_stream() {
        let (mut journey, received) = create_initial_message("store://incoming/1");
        let assigned = create_metadata_only_message(&received, MessageCreationSource::Assignment);
        append_message_to_journey(&mut journey, &assigned);

        assert_eq!(received.journey_id, assigned.journey_id);
        assert_ne!(received.message_id, assigned.message_id);
        assert_eq!(received.stream_ref.stream_id, assigned.stream_ref.stream_id);
        assert_eq!(journey.messages.len(), 2);
    }

    #[test]
    fn transformation_creates_new_message_and_new_stream() {
        let (mut journey, received) = create_initial_message("store://incoming/1");
        let transformed = create_derived_message(
            &received,
            "store://transformed/1",
            MessageCreationSource::Transformation,
        );
        append_message_to_journey(&mut journey, &transformed);

        assert_eq!(received.journey_id, transformed.journey_id);
        assert_ne!(received.message_id, transformed.message_id);
        assert_ne!(received.stream_ref.stream_id, transformed.stream_ref.stream_id);
        assert_eq!(journey.messages.len(), 2);
    }

    #[test]
    fn message_treatment_is_independent_of_format_or_size() {
        let treatment = MessageTreatment {
            priority: MessagePriority::Immediate,
            execution_profile: ExecutionProfile::Conversation,
            durability: MessageDurability::Ephemeral,
        };

        let (_journey, message) = create_initial_message_with_treatment(
            "store://incoming/tiny-text",
            treatment,
        );

        assert_eq!(message.priority, MessagePriority::Immediate);
        assert_eq!(message.execution_profile, ExecutionProfile::Conversation);
        assert_eq!(message.durability, MessageDurability::Ephemeral);
    }

    #[test]
    fn derived_message_keeps_treatment() {
        let treatment = MessageTreatment {
            priority: MessagePriority::Background,
            execution_profile: ExecutionProfile::PassThrough,
            durability: MessageDurability::Durable,
        };
        let (_journey, received) = create_initial_message_with_treatment(
            "store://incoming/heavy",
            treatment,
        );
        let moved = create_derived_message(
            &received,
            "store://outgoing/heavy",
            MessageCreationSource::SendPreparation,
        );

        assert_eq!(moved.priority, MessagePriority::Background);
        assert_eq!(moved.execution_profile, ExecutionProfile::PassThrough);
        assert_eq!(moved.durability, MessageDurability::Durable);
    }
}
