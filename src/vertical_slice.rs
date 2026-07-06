use crate::journey_model::{
    append_message_to_journey, create_derived_message, create_initial_message_with_treatment,
    create_metadata_only_message, ExecutionProfile, Journey, Message, MessageCreationSource,
    MessageDurability, MessagePriority, MessageTreatment,
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RuntimeEvent {
    FileReceived { stream_uri: String },
    HttpRequestReceived { stream_uri: String },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ReceivedWork {
    pub journey: Journey,
    pub message: Message,
}

pub fn receive_event(event: RuntimeEvent, treatment: MessageTreatment) -> ReceivedWork {
    let stream_uri = match event {
        RuntimeEvent::FileReceived { stream_uri } => stream_uri,
        RuntimeEvent::HttpRequestReceived { stream_uri } => stream_uri,
    };

    let (journey, message) = create_initial_message_with_treatment(stream_uri, treatment);

    ReceivedWork { journey, message }
}

pub fn apply_assignment(journey: &mut Journey, message: &Message) -> Message {
    let assigned = create_metadata_only_message(message, MessageCreationSource::Assignment);
    append_message_to_journey(journey, &assigned);
    assigned
}

pub fn apply_transformation(
    journey: &mut Journey,
    message: &Message,
    transformed_stream_uri: impl Into<String>,
) -> Message {
    let transformed = create_derived_message(
        message,
        transformed_stream_uri,
        MessageCreationSource::Transformation,
    );
    append_message_to_journey(journey, &transformed);
    transformed
}

pub fn conversation_treatment() -> MessageTreatment {
    MessageTreatment {
        priority: MessagePriority::Immediate,
        execution_profile: ExecutionProfile::Conversation,
        durability: MessageDurability::Ephemeral,
    }
}

pub fn business_treatment() -> MessageTreatment {
    MessageTreatment {
        priority: MessagePriority::Normal,
        execution_profile: ExecutionProfile::Business,
        durability: MessageDurability::Recoverable,
    }
}

pub fn pass_through_treatment() -> MessageTreatment {
    MessageTreatment {
        priority: MessagePriority::Background,
        execution_profile: ExecutionProfile::PassThrough,
        durability: MessageDurability::Durable,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn receives_file_as_journey_message_stream() {
        let work = receive_event(
            RuntimeEvent::FileReceived {
                stream_uri: "store://incoming/file-1".to_string(),
            },
            business_treatment(),
        );

        assert_eq!(work.journey.journey_id, work.message.journey_id);
        assert_eq!(work.journey.messages.len(), 1);
        assert_eq!(work.message.execution_profile, ExecutionProfile::Business);
    }

    #[test]
    fn assignment_and_transformation_preserve_journey() {
        let mut work = receive_event(
            RuntimeEvent::HttpRequestReceived {
                stream_uri: "store://incoming/http-1".to_string(),
            },
            business_treatment(),
        );

        let assigned = apply_assignment(&mut work.journey, &work.message);
        let transformed = apply_transformation(
            &mut work.journey,
            &assigned,
            "store://outgoing/transformed-1",
        );

        assert_eq!(work.message.journey_id, assigned.journey_id);
        assert_eq!(assigned.journey_id, transformed.journey_id);
        assert_eq!(work.journey.messages.len(), 3);
        assert_eq!(work.message.stream_ref.stream_id, assigned.stream_ref.stream_id);
        assert_ne!(assigned.stream_ref.stream_id, transformed.stream_ref.stream_id);
    }
}
