use std::collections::HashSet;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiveClaimMode {
    Shared,
    Exclusive,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiveClaim {
    pub mode: ReceiveClaimMode,
    pub resource: String,
}

#[derive(Debug, Default)]
pub struct ReceiveClaimRegistry {
    exclusive: HashSet<String>,
}

impl ReceiveClaimRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn claim(&mut self, claim: &ReceiveClaim) -> Result<(), String> {
        match claim.mode {
            ReceiveClaimMode::Shared => Ok(()),
            ReceiveClaimMode::Exclusive => {
                if self.exclusive.contains(&claim.resource) {
                    Err(format!("exclusive receive resource already claimed: {}", claim.resource))
                } else {
                    self.exclusive.insert(claim.resource.clone());
                    Ok(())
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shared_claims_do_not_conflict() {
        let mut registry = ReceiveClaimRegistry::new();
        let claim = ReceiveClaim { mode: ReceiveClaimMode::Shared, resource: "http-port-8080".to_string() };

        assert!(registry.claim(&claim).is_ok());
        assert!(registry.claim(&claim).is_ok());
    }

    #[test]
    fn exclusive_claims_conflict_on_same_resource() {
        let mut registry = ReceiveClaimRegistry::new();
        let claim = ReceiveClaim { mode: ReceiveClaimMode::Exclusive, resource: "directory-orders".to_string() };

        assert!(registry.claim(&claim).is_ok());
        assert!(registry.claim(&claim).is_err());
    }
}
