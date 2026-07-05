#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ProtocolDependency {
    pub child: &'static str,
    pub parent: &'static str,
}

pub const PROTOCOL_DEPENDENCIES: &[ProtocolDependency] = &[
    ProtocolDependency { child: "mllp", parent: "tcp" },
    ProtocolDependency { child: "hl7v2", parent: "mllp" },
    ProtocolDependency { child: "http", parent: "tcp" },
    ProtocolDependency { child: "fhir", parent: "http" },
    ProtocolDependency { child: "nmea2000", parent: "canbus" },
    ProtocolDependency { child: "mqtt", parent: "tcp" },
    ProtocolDependency { child: "mqtt-sn", parent: "udp" },
];

pub fn parent_of(child: &str) -> Option<&'static str> {
    PROTOCOL_DEPENDENCIES
        .iter()
        .find(|entry| entry.child == child)
        .map(|entry| entry.parent)
}

pub fn depends_on(child: &str, ancestor: &str) -> bool {
    let mut current = Some(child);

    while let Some(id) = current {
        if id == ancestor {
            return true;
        }
        current = parent_of(id);
    }

    false
}

pub fn chain_to_root(child: &str) -> Vec<&'static str> {
    let mut result = Vec::new();
    let mut current = Some(child);

    while let Some(id) = current {
        result.push(id);
        current = parent_of(id);
    }

    result
}
