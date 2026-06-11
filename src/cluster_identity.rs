#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmipCluster(pub String);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmipNode(pub String);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmipHost(pub String);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct XmipRuntimePlace {
    pub cluster: XmipCluster,
    pub node: XmipNode,
    pub host: XmipHost,
}

impl XmipRuntimePlace {
    pub fn same_cluster_as(&self, other: &XmipRuntimePlace) -> bool {
        self.cluster == other.cluster
    }
}
