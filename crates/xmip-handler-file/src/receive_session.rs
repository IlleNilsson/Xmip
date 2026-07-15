use std::sync::Arc;
use std::time::{Duration, SystemTime};

use xmip_core::{
    create_initial_message, Journey, Message, ReceiveOwner, ReceiveOwnershipError,
    ReceiveOwnershipLease, ReceiveOwnershipStore,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileReceiveError {
    Ownership(ReceiveOwnershipError),
    OwnershipLost {
        receive_location_name: String,
        expected_owner: ReceiveOwner,
    },
}

impl From<ReceiveOwnershipError> for FileReceiveError {
    fn from(value: ReceiveOwnershipError) -> Self {
        Self::Ownership(value)
    }
}

/// Owns one FILE Receive Location on one Node in one Host Process.
///
/// The session may accept files only while its exclusive lease is current.
/// A received Stream is handed to the Receive Port boundary, represented here
/// by creation of the initial Message and Journey.
pub struct FileReceiveSession<S: ReceiveOwnershipStore> {
    store: Arc<S>,
    receive_location_name: String,
    owner: ReceiveOwner,
    lease_duration: Duration,
}

impl<S: ReceiveOwnershipStore> FileReceiveSession<S> {
    #[must_use]
    pub fn new(
        store: Arc<S>,
        receive_location_name: impl Into<String>,
        owner: ReceiveOwner,
        lease_duration: Duration,
    ) -> Self {
        Self {
            store,
            receive_location_name: receive_location_name.into(),
            owner,
            lease_duration,
        }
    }

    pub fn acquire(&self, now: SystemTime) -> Result<ReceiveOwnershipLease, FileReceiveError> {
        self.store
            .acquire(
                &self.receive_location_name,
                self.owner.clone(),
                self.lease_duration,
                now,
            )
            .map_err(Into::into)
    }

    pub fn renew(&self, now: SystemTime) -> Result<ReceiveOwnershipLease, FileReceiveError> {
        self.store
            .renew(
                &self.receive_location_name,
                &self.owner,
                self.lease_duration,
                now,
            )
            .map_err(Into::into)
    }

    pub fn release(&self) -> Result<(), FileReceiveError> {
        self.store
            .release(&self.receive_location_name, &self.owner)
            .map_err(Into::into)
    }

    pub fn receive(
        &self,
        stream_uri: impl Into<String>,
        now: SystemTime,
    ) -> Result<(Journey, Message), FileReceiveError> {
        let current = self
            .store
            .current(&self.receive_location_name, now)?;

        let owned = current
            .as_ref()
            .is_some_and(|lease| lease.owner == self.owner && !lease.is_expired_at(now));

        if !owned {
            return Err(FileReceiveError::OwnershipLost {
                receive_location_name: self.receive_location_name.clone(),
                expected_owner: self.owner.clone(),
            });
        }

        Ok(create_initial_message(stream_uri))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use xmip_core::{InMemoryReceiveOwnershipStore, MessageCreationSource};

    fn now() -> SystemTime {
        SystemTime::UNIX_EPOCH + Duration::from_secs(10_000)
    }

    #[test]
    fn owner_can_receive_and_receive_port_boundary_creates_message_and_journey() {
        let store = Arc::new(InMemoryReceiveOwnershipStore::default());
        let session = FileReceiveSession::new(
            store,
            "orders-file",
            ReceiveOwner::new("node-a", "file-host-1"),
            Duration::from_secs(30),
        );

        session.acquire(now()).expect("ownership must be acquired");
        let (journey, message) = session
            .receive("file:///incoming/order-1.xml", now())
            .expect("owner must receive");

        assert_eq!(journey.journey_id, message.journey_id);
        assert_eq!(journey.messages.len(), 1);
        assert_eq!(message.created_by, MessageCreationSource::Receive);
        assert!(message.stream_ref.immutable);
    }

    #[test]
    fn process_without_ownership_cannot_receive_the_same_location() {
        let store = Arc::new(InMemoryReceiveOwnershipStore::default());
        let owner = FileReceiveSession::new(
            Arc::clone(&store),
            "orders-file",
            ReceiveOwner::new("node-a", "file-host-1"),
            Duration::from_secs(30),
        );
        let intruder = FileReceiveSession::new(
            store,
            "orders-file",
            ReceiveOwner::new("node-b", "file-host-2"),
            Duration::from_secs(30),
        );

        owner.acquire(now()).expect("first process must own");

        assert!(matches!(
            intruder.receive("file:///incoming/order-1.xml", now()),
            Err(FileReceiveError::OwnershipLost { .. })
        ));
    }

    #[test]
    fn expired_owner_cannot_receive() {
        let store = Arc::new(InMemoryReceiveOwnershipStore::default());
        let session = FileReceiveSession::new(
            store,
            "orders-file",
            ReceiveOwner::new("node-a", "file-host-1"),
            Duration::from_secs(5),
        );

        session.acquire(now()).expect("ownership must be acquired");

        assert!(matches!(
            session.receive(
                "file:///incoming/order-1.xml",
                now() + Duration::from_secs(6)
            ),
            Err(FileReceiveError::OwnershipLost { .. })
        ));
    }
}
