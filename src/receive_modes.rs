#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReceiveAcquisitionMode {
    DirectIncoming,
    SoughtForIncoming,
    ResourceEventIncoming,
    BrokerEventIncoming,
    ScheduledIncoming,
}
