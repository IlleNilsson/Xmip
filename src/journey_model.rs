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
pub struct XmipMessage {
    pub journey_id: Uuid,
    pub message_id: Uuid,
    pub stream_ref: StreamRef,
    pub generation: u32,
    pub created_by: MessageCreationSource,
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

pub fn create_initial_message(stream_uri: impl Into<String>) -> (Journey, XmipMessage) {
    let journey_id = Uuid::new_v4();
    let message_id = Uuid::new_v4();
    let stream_id = Uuid::new_v4();

    let message = XmipMessage {
        journey_id,
        message_id,
        stream_ref: StreamRef {
            stream_id,
            uri: stream_uri.into(),
            immutable: true,
        },
        generation: 0,
        created_by: MessageCreationSource::Receive,
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
    previous: &XmipMessage,
    stream_uri: impl Into<String>,
    created_by: MessageCreationSource,
) -> XmipMessage {
    XmipMessage {
        journey_id: previous.journey_id,
        message_id: Uuid::new_v4(),
        stream_ref: StreamRef {
            stream_id: Uuid::new_v4(),
            uri: stream_uri.into(),
            immutable: true,
        },
        generation: previous.generation + 1,
        created_by,
    }
}

pub fn create_metadata_only_message(
    previous: &XmipMessage,
    created_by: MessageCreationSource,
) -> XmipMessage {
    XmipMessage {
        journey_id: previous.journey_id,
        message_id: Uuid::new_v4(),
        stream_ref: previous.stream_ref.clone(),
        generation: previous.generation + 1,
        created_by,
    }
}

pub fn append_message_to_journey(journey: &mut Journey, message: &XmipMessage) {
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
}
