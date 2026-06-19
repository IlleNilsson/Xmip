#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum HandlerSpace {
    FileTransfer,
    NetworkWeb,
    MessagingStreaming,
    Healthcare,
    IndustrialIoT,
    EnergyUtilities,
    FinancePayments,
    BusinessDocuments,
    DatabaseStorage,
    EmailCollaboration,
    EnterpriseSaaS,
    IdentityDirectory,
    GovernmentExchange,
    Geospatial,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HandlerRepository {
    pub repository_name: &'static str,
    pub submodule_path: &'static str,
    pub space: HandlerSpace,
}
