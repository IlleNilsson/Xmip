use std::collections::HashSet;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiveClaimMode {
    Shared,
    Exclusive,
    Pattern,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReceiveClaim {
    pub mode: ReceiveClaimMode,
    pub resource: String,
}

#[derive(Debug, Default)]
pub struct ReceiveClaimRegistry {
    exclusive: HashSet<String>,
    patterns: HashSet<String>,
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
            ReceiveClaimMode::Pattern => {
                if self.patterns.contains(&claim.resource) {
                    Err(format!("receive pattern already claimed: {}", claim.resource))
                } else {
                    self.patterns.insert(claim.resource.clone());
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

    #[test]
    fn queue_pattern_claims_conflict_on_same_pattern() {
        let mut registry = ReceiveClaimRegistry::new();
        let claim = ReceiveClaim { mode: ReceiveClaimMode::Pattern, resource: "queue-orders|subject=invoice.created".to_string() };

        assert!(registry.claim(&claim).is_ok());
        assert!(registry.claim(&claim).is_err());
    }

    #[test]
    fn queue_pattern_claims_allow_different_patterns_on_same_queue() {
        let mut registry = ReceiveClaimRegistry::new();
        let invoice = ReceiveClaim { mode: ReceiveClaimMode::Pattern, resource: "queue-orders|subject=invoice.created".to_string() };
        let shipment = ReceiveClaim { mode: ReceiveClaimMode::Pattern, resource: "queue-orders|subject=shipment.created".to_string() };

        assert!(registry.claim(&invoice).is_ok());
        assert!(registry.claim(&shipment).is_ok());
    }
}
