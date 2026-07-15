use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ExclusivenessScope {
    Cluster,
    Node,
    Process,
    Resource,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ExclusiveAction {
    Receive,
    Process,
    Send,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ExclusiveOwner {
    pub cluster_name: String,
    pub node_name: String,
    pub host_process_name: String,
}

impl ExclusiveOwner {
    pub fn new(cluster: impl Into<String>, node: impl Into<String>, process: impl Into<String>) -> Self {
        Self {
            cluster_name: cluster.into(),
            node_name: node.into(),
            host_process_name: process.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ExclusivenessBoundary {
    pub scope: ExclusivenessScope,
    pub key: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExclusiveRequest {
    pub task_id: Uuid,
    pub action: ExclusiveAction,
    pub boundary: ExclusivenessBoundary,
    pub owner: ExclusiveOwner,
    pub requested_at: SystemTime,
    pub acquire_timeout: Duration,
    pub lease_duration: Duration,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExclusiveLease {
    pub request: ExclusiveRequest,
    pub acquired_at: SystemTime,
    pub expires_at: SystemTime,
}

impl ExclusiveLease {
    pub fn is_expired_at(&self, now: SystemTime) -> bool {
        self.expires_at <= now
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AcquireOutcome {
    Acquired(ExclusiveLease),
    Queued { position: usize },
    TimedOut,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExclusivenessError {
    InvalidDuration,
    NotHolder,
    NotFound,
    StoreUnavailable,
}

pub trait ExclusivenessStore: Send + Sync {
    fn request(&self, request: ExclusiveRequest, now: SystemTime) -> Result<AcquireOutcome, ExclusivenessError>;
    fn poll(&self, task_id: Uuid, now: SystemTime) -> Result<AcquireOutcome, ExclusivenessError>;
    fn renew(&self, task_id: Uuid, now: SystemTime) -> Result<ExclusiveLease, ExclusivenessError>;
    fn release(&self, task_id: Uuid, now: SystemTime) -> Result<(), ExclusivenessError>;
}

#[derive(Default)]
struct State {
    holders: HashMap<ExclusivenessBoundary, ExclusiveLease>,
    queues: HashMap<ExclusivenessBoundary, VecDeque<ExclusiveRequest>>,
}

#[derive(Clone, Default)]
pub struct InMemoryExclusivenessStore {
    state: Arc<Mutex<State>>,
}

impl InMemoryExclusivenessStore {
    fn lock(&self) -> Result<std::sync::MutexGuard<'_, State>, ExclusivenessError> {
        self.state.lock().map_err(|_| ExclusivenessError::StoreUnavailable)
    }

    fn expire_and_promote(state: &mut State, boundary: &ExclusivenessBoundary, now: SystemTime) {
        if state.holders.get(boundary).is_some_and(|lease| lease.is_expired_at(now)) {
            state.holders.remove(boundary);
        }

        if state.holders.contains_key(boundary) {
            return;
        }

        let Some(queue) = state.queues.get_mut(boundary) else { return; };
        while let Some(request) = queue.pop_front() {
            if now.duration_since(request.requested_at).unwrap_or_default() >= request.acquire_timeout {
                continue;
            }
            let lease = ExclusiveLease {
                acquired_at: now,
                expires_at: now + request.lease_duration,
                request,
            };
            state.holders.insert(boundary.clone(), lease);
            break;
        }
    }
}

impl ExclusivenessStore for InMemoryExclusivenessStore {
    fn request(&self, request: ExclusiveRequest, now: SystemTime) -> Result<AcquireOutcome, ExclusivenessError> {
        if request.acquire_timeout.is_zero() || request.lease_duration.is_zero() {
            return Err(ExclusivenessError::InvalidDuration);
        }
        let mut state = self.lock()?;
        Self::expire_and_promote(&mut state, &request.boundary, now);
        if !state.holders.contains_key(&request.boundary) {
            let lease = ExclusiveLease {
                acquired_at: now,
                expires_at: now + request.lease_duration,
                request,
            };
            state.holders.insert(lease.request.boundary.clone(), lease.clone());
            return Ok(AcquireOutcome::Acquired(lease));
        }
        let queue = state.queues.entry(request.boundary.clone()).or_default();
        queue.push_back(request);
        Ok(AcquireOutcome::Queued { position: queue.len() })
    }

    fn poll(&self, task_id: Uuid, now: SystemTime) -> Result<AcquireOutcome, ExclusivenessError> {
        let mut state = self.lock()?;
        let boundaries: Vec<_> = state.holders.keys().cloned().chain(state.queues.keys().cloned()).collect();
        for boundary in boundaries {
            Self::expire_and_promote(&mut state, &boundary, now);
            if let Some(lease) = state.holders.get(&boundary) {
                if lease.request.task_id == task_id {
                    return Ok(AcquireOutcome::Acquired(lease.clone()));
                }
            }
            if let Some(queue) = state.queues.get(&boundary) {
                if let Some((position, request)) = queue.iter().enumerate().find(|(_, r)| r.task_id == task_id) {
                    if now.duration_since(request.requested_at).unwrap_or_default() >= request.acquire_timeout {
                        return Ok(AcquireOutcome::TimedOut);
                    }
                    return Ok(AcquireOutcome::Queued { position: position + 1 });
                }
            }
        }
        Err(ExclusivenessError::NotFound)
    }

    fn renew(&self, task_id: Uuid, now: SystemTime) -> Result<ExclusiveLease, ExclusivenessError> {
        let mut state = self.lock()?;
        let Some(lease) = state.holders.values_mut().find(|lease| lease.request.task_id == task_id) else {
            return Err(ExclusivenessError::NotHolder);
        };
        if lease.is_expired_at(now) {
            return Err(ExclusivenessError::NotHolder);
        }
        lease.expires_at = now + lease.request.lease_duration;
        Ok(lease.clone())
    }

    fn release(&self, task_id: Uuid, now: SystemTime) -> Result<(), ExclusivenessError> {
        let mut state = self.lock()?;
        let Some(boundary) = state.holders.iter().find_map(|(key, lease)| (lease.request.task_id == task_id).then(|| key.clone())) else {
            return Err(ExclusivenessError::NotHolder);
        };
        state.holders.remove(&boundary);
        Self::expire_and_promote(&mut state, &boundary, now);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(action: ExclusiveAction, key: &str, owner: &str, now: SystemTime) -> ExclusiveRequest {
        ExclusiveRequest {
            task_id: Uuid::new_v4(),
            action,
            boundary: ExclusivenessBoundary { scope: ExclusivenessScope::Resource, key: key.into() },
            owner: ExclusiveOwner::new("cluster-a", "node-a", owner),
            requested_at: now,
            acquire_timeout: Duration::from_secs(30),
            lease_duration: Duration::from_secs(5),
        }
    }

    #[test]
    fn receive_process_and_send_share_the_same_exclusive_boundary() {
        let store = InMemoryExclusivenessStore::default();
        let now = SystemTime::UNIX_EPOCH + Duration::from_secs(100);
        let first = request(ExclusiveAction::Receive, "resource-a", "host-1", now);
        let second = request(ExclusiveAction::Send, "resource-a", "host-2", now);
        assert!(matches!(store.request(first, now).unwrap(), AcquireOutcome::Acquired(_)));
        assert_eq!(store.request(second, now).unwrap(), AcquireOutcome::Queued { position: 1 });
    }

    #[test]
    fn release_promotes_first_queued_task() {
        let store = InMemoryExclusivenessStore::default();
        let now = SystemTime::UNIX_EPOCH + Duration::from_secs(100);
        let first = request(ExclusiveAction::Process, "resource-a", "host-1", now);
        let second = request(ExclusiveAction::Send, "resource-a", "host-2", now);
        let first_id = first.task_id;
        let second_id = second.task_id;
        store.request(first, now).unwrap();
        store.request(second, now).unwrap();
        store.release(first_id, now + Duration::from_secs(1)).unwrap();
        assert!(matches!(store.poll(second_id, now + Duration::from_secs(1)).unwrap(), AcquireOutcome::Acquired(_)));
    }
}
