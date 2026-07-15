use std::sync::Arc;
use std::time::{Duration, SystemTime};

use uuid::Uuid;
use xmip_core::{create_initial_message, Journey, Message};
use xmip_exclusiveness::{
    AcquireOutcome, ExclusiveAction, ExclusiveOwner, ExclusiveRequest, ExclusivenessBoundary,
    ExclusivenessError, ExclusivenessScope, ExclusivenessStore,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileReceiveError {
    Exclusiveness(ExclusivenessError),
    NotAcquired,
    TimedOut,
}

impl From<ExclusivenessError> for FileReceiveError {
    fn from(value: ExclusivenessError) -> Self {
        Self::Exclusiveness(value)
    }
}

/// FILE receive uses Resource-scoped exclusiveness.
///
/// The Receive Port boundary creates the initial Message and Journey only after
/// the exclusive task has acquired its configured resource.
pub struct FileReceiveSession<S: ExclusivenessStore> {
    store: Arc<S>,
    request: ExclusiveRequest,
}

impl<S: ExclusivenessStore> FileReceiveSession<S> {
    #[must_use]
    pub fn new(
        store: Arc<S>,
        cluster_name: impl Into<String>,
        node_name: impl Into<String>,
        host_process_name: impl Into<String>,
        resource_key: impl Into<String>,
        acquire_timeout: Duration,
        lease_duration: Duration,
        requested_at: SystemTime,
    ) -> Self {
        Self {
            store,
            request: ExclusiveRequest {
                task_id: Uuid::new_v4(),
                action: ExclusiveAction::Receive,
                boundary: ExclusivenessBoundary {
                    scope: ExclusivenessScope::Resource,
                    key: resource_key.into(),
                },
                owner: ExclusiveOwner::new(cluster_name, node_name, host_process_name),
                requested_at,
                acquire_timeout,
                lease_duration,
            },
        }
    }

    pub fn acquire(&self, now: SystemTime) -> Result<AcquireOutcome, FileReceiveError> {
        self.store.request(self.request.clone(), now).map_err(Into::into)
    }

    pub fn renew(&self, now: SystemTime) -> Result<(), FileReceiveError> {
        self.store.renew(self.request.task_id, now)?;
        Ok(())
    }

    pub fn release(&self, now: SystemTime) -> Result<(), FileReceiveError> {
        self.store.release(self.request.task_id, now).map_err(Into::into)
    }

    pub fn receive(
        &self,
        stream_uri: impl Into<String>,
        now: SystemTime,
    ) -> Result<(Journey, Message), FileReceiveError> {
        match self.store.poll(self.request.task_id, now)? {
            AcquireOutcome::Acquired(_) => Ok(create_initial_message(stream_uri)),
            AcquireOutcome::Queued { .. } => Err(FileReceiveError::NotAcquired),
            AcquireOutcome::TimedOut => Err(FileReceiveError::TimedOut),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use xmip_core::MessageCreationSource;
    use xmip_exclusiveness::InMemoryExclusivenessStore;

    fn now() -> SystemTime {
        SystemTime::UNIX_EPOCH + Duration::from_secs(10_000)
    }

    fn session(
        store: Arc<InMemoryExclusivenessStore>,
        host: &str,
    ) -> FileReceiveSession<InMemoryExclusivenessStore> {
        FileReceiveSession::new(
            store,
            "cluster-a",
            "node-a",
            host,
            "file:///incoming/orders",
            Duration::from_secs(30),
            Duration::from_secs(5),
            now(),
        )
    }

    #[test]
    fn acquired_resource_creates_message_and_journey() {
        let store = Arc::new(InMemoryExclusivenessStore::default());
        let owner = session(store, "file-host-1");
        assert!(matches!(owner.acquire(now()).unwrap(), AcquireOutcome::Acquired(_)));

        let (journey, message) = owner
            .receive("file:///incoming/orders/order-1.xml", now())
            .expect("exclusive owner must receive");

        assert_eq!(journey.journey_id, message.journey_id);
        assert_eq!(message.created_by, MessageCreationSource::Receive);
        assert!(message.stream_ref.immutable);
    }

    #[test]
    fn competing_file_receive_is_queued() {
        let store = Arc::new(InMemoryExclusivenessStore::default());
        let first = session(Arc::clone(&store), "file-host-1");
        let second = session(store, "file-host-2");

        assert!(matches!(first.acquire(now()).unwrap(), AcquireOutcome::Acquired(_)));
        assert_eq!(second.acquire(now()).unwrap(), AcquireOutcome::Queued { position: 1 });
        assert_eq!(
            second.receive("file:///incoming/orders/order-1.xml", now()),
            Err(FileReceiveError::NotAcquired)
        );
    }

    #[test]
    fn queued_receive_is_promoted_after_release() {
        let store = Arc::new(InMemoryExclusivenessStore::default());
        let first = session(Arc::clone(&store), "file-host-1");
        let second = session(store, "file-host-2");

        first.acquire(now()).unwrap();
        second.acquire(now()).unwrap();
        first.release(now() + Duration::from_secs(1)).unwrap();

        assert!(second
            .receive(
                "file:///incoming/orders/order-2.xml",
                now() + Duration::from_secs(1)
            )
            .is_ok());
    }
}
