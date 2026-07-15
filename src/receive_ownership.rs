use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};

/// Identifies the single Node and Host Process allowed to receive from a configured Receive Location.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ReceiveOwner {
    pub node_name: String,
    pub host_process_name: String,
}

impl ReceiveOwner {
    #[must_use]
    pub fn new(node_name: impl Into<String>, host_process_name: impl Into<String>) -> Self {
        Self {
            node_name: node_name.into(),
            host_process_name: host_process_name.into(),
        }
    }
}

/// A time-bounded exclusive claim for one Receive Location.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiveOwnershipLease {
    pub receive_location_name: String,
    pub owner: ReceiveOwner,
    pub acquired_at: SystemTime,
    pub expires_at: SystemTime,
}

impl ReceiveOwnershipLease {
    #[must_use]
    pub fn is_expired_at(&self, now: SystemTime) -> bool {
        self.expires_at <= now
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiveOwnershipError {
    AlreadyOwned {
        receive_location_name: String,
        current_owner: ReceiveOwner,
    },
    NotOwned {
        receive_location_name: String,
    },
    OwnedByAnother {
        receive_location_name: String,
        current_owner: ReceiveOwner,
    },
    InvalidLeaseDuration,
    StoreUnavailable,
}

/// Atomic ownership operations required from a durable cluster-aware implementation.
///
/// FILE and equivalent receive protocols must call this boundary before receiving.
/// At any instant, one Receive Location can be owned by only one Host Process on one Node.
pub trait ReceiveOwnershipStore: Send + Sync {
    fn acquire(
        &self,
        receive_location_name: &str,
        owner: ReceiveOwner,
        lease_duration: Duration,
        now: SystemTime,
    ) -> Result<ReceiveOwnershipLease, ReceiveOwnershipError>;

    fn renew(
        &self,
        receive_location_name: &str,
        owner: &ReceiveOwner,
        lease_duration: Duration,
        now: SystemTime,
    ) -> Result<ReceiveOwnershipLease, ReceiveOwnershipError>;

    fn release(
        &self,
        receive_location_name: &str,
        owner: &ReceiveOwner,
    ) -> Result<(), ReceiveOwnershipError>;

    fn current(
        &self,
        receive_location_name: &str,
        now: SystemTime,
    ) -> Result<Option<ReceiveOwnershipLease>, ReceiveOwnershipError>;
}

/// Development and test implementation. Production uses an atomic durable store.
#[derive(Debug, Clone, Default)]
pub struct InMemoryReceiveOwnershipStore {
    leases: Arc<Mutex<HashMap<String, ReceiveOwnershipLease>>>,
}

impl InMemoryReceiveOwnershipStore {
    fn lock(
        &self,
    ) -> Result<std::sync::MutexGuard<'_, HashMap<String, ReceiveOwnershipLease>>, ReceiveOwnershipError>
    {
        self.leases
            .lock()
            .map_err(|_| ReceiveOwnershipError::StoreUnavailable)
    }
}

impl ReceiveOwnershipStore for InMemoryReceiveOwnershipStore {
    fn acquire(
        &self,
        receive_location_name: &str,
        owner: ReceiveOwner,
        lease_duration: Duration,
        now: SystemTime,
    ) -> Result<ReceiveOwnershipLease, ReceiveOwnershipError> {
        if lease_duration.is_zero() {
            return Err(ReceiveOwnershipError::InvalidLeaseDuration);
        }

        let mut leases = self.lock()?;
        if let Some(existing) = leases.get(receive_location_name) {
            if !existing.is_expired_at(now) && existing.owner != owner {
                return Err(ReceiveOwnershipError::AlreadyOwned {
                    receive_location_name: receive_location_name.to_string(),
                    current_owner: existing.owner.clone(),
                });
            }
        }

        let lease = ReceiveOwnershipLease {
            receive_location_name: receive_location_name.to_string(),
            owner,
            acquired_at: now,
            expires_at: now + lease_duration,
        };
        leases.insert(receive_location_name.to_string(), lease.clone());
        Ok(lease)
    }

    fn renew(
        &self,
        receive_location_name: &str,
        owner: &ReceiveOwner,
        lease_duration: Duration,
        now: SystemTime,
    ) -> Result<ReceiveOwnershipLease, ReceiveOwnershipError> {
        if lease_duration.is_zero() {
            return Err(ReceiveOwnershipError::InvalidLeaseDuration);
        }

        let mut leases = self.lock()?;
        let Some(existing) = leases.get(receive_location_name) else {
            return Err(ReceiveOwnershipError::NotOwned {
                receive_location_name: receive_location_name.to_string(),
            });
        };

        if existing.owner != *owner || existing.is_expired_at(now) {
            return Err(ReceiveOwnershipError::OwnedByAnother {
                receive_location_name: receive_location_name.to_string(),
                current_owner: existing.owner.clone(),
            });
        }

        let renewed = ReceiveOwnershipLease {
            receive_location_name: receive_location_name.to_string(),
            owner: owner.clone(),
            acquired_at: existing.acquired_at,
            expires_at: now + lease_duration,
        };
        leases.insert(receive_location_name.to_string(), renewed.clone());
        Ok(renewed)
    }

    fn release(
        &self,
        receive_location_name: &str,
        owner: &ReceiveOwner,
    ) -> Result<(), ReceiveOwnershipError> {
        let mut leases = self.lock()?;
        let Some(existing) = leases.get(receive_location_name) else {
            return Err(ReceiveOwnershipError::NotOwned {
                receive_location_name: receive_location_name.to_string(),
            });
        };

        if existing.owner != *owner {
            return Err(ReceiveOwnershipError::OwnedByAnother {
                receive_location_name: receive_location_name.to_string(),
                current_owner: existing.owner.clone(),
            });
        }

        leases.remove(receive_location_name);
        Ok(())
    }

    fn current(
        &self,
        receive_location_name: &str,
        now: SystemTime,
    ) -> Result<Option<ReceiveOwnershipLease>, ReceiveOwnershipError> {
        let mut leases = self.lock()?;
        if leases
            .get(receive_location_name)
            .is_some_and(|lease| lease.is_expired_at(now))
        {
            leases.remove(receive_location_name);
        }
        Ok(leases.get(receive_location_name).cloned())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn owner(node: &str, process: &str) -> ReceiveOwner {
        ReceiveOwner::new(node, process)
    }

    #[test]
    fn only_one_node_and_process_can_own_a_receive_location() {
        let store = InMemoryReceiveOwnershipStore::default();
        let now = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000);

        store
            .acquire(
                "orders-file",
                owner("node-a", "host-1"),
                Duration::from_secs(30),
                now,
            )
            .expect("first owner must acquire");

        let error = store
            .acquire(
                "orders-file",
                owner("node-b", "host-2"),
                Duration::from_secs(30),
                now,
            )
            .expect_err("second owner must be rejected");

        assert_eq!(
            error,
            ReceiveOwnershipError::AlreadyOwned {
                receive_location_name: "orders-file".to_string(),
                current_owner: owner("node-a", "host-1"),
            }
        );
    }

    #[test]
    fn expired_ownership_can_move_to_another_node_and_process() {
        let store = InMemoryReceiveOwnershipStore::default();
        let now = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000);

        store
            .acquire(
                "orders-file",
                owner("node-a", "host-1"),
                Duration::from_secs(5),
                now,
            )
            .expect("first owner must acquire");

        let replacement = store
            .acquire(
                "orders-file",
                owner("node-b", "host-2"),
                Duration::from_secs(30),
                now + Duration::from_secs(6),
            )
            .expect("expired ownership must be replaceable");

        assert_eq!(replacement.owner, owner("node-b", "host-2"));
    }

    #[test]
    fn another_process_cannot_release_the_owner() {
        let store = InMemoryReceiveOwnershipStore::default();
        let now = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000);

        store
            .acquire(
                "orders-file",
                owner("node-a", "host-1"),
                Duration::from_secs(30),
                now,
            )
            .expect("owner must acquire");

        assert!(matches!(
            store.release("orders-file", &owner("node-a", "host-2")),
            Err(ReceiveOwnershipError::OwnedByAnother { .. })
        ));
    }
}
