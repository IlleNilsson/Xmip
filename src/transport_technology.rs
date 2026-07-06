use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct TransportTechnology {
    pub name: String,
    pub layer: TransportTechnologyLayer,
    pub built_on: Vec<String>,
    pub reusable_by: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum TransportTechnologyLayer {
    Network,
    Transport,
    Session,
    Application,
}

pub fn core_transport_tree() -> Vec<TransportTechnology> {
    vec![
        TransportTechnology {
            name: "ip".to_string(),
            layer: TransportTechnologyLayer::Network,
            built_on: Vec::new(),
            reusable_by: vec!["tcp".to_string(), "udp".to_string()],
        },
        TransportTechnology {
            name: "tcp".to_string(),
            layer: TransportTechnologyLayer::Transport,
            built_on: vec!["ip".to_string()],
            reusable_by: vec![
                "http".to_string(),
                "grpc".to_string(),
                "ftp".to_string(),
                "sftp".to_string(),
                "mllp".to_string(),
                "mqtt".to_string(),
            ],
        },
        TransportTechnology {
            name: "udp".to_string(),
            layer: TransportTechnologyLayer::Transport,
            built_on: vec!["ip".to_string()],
            reusable_by: vec!["dns".to_string(), "syslog".to_string()],
        },
        TransportTechnology {
            name: "http".to_string(),
            layer: TransportTechnologyLayer::Application,
            built_on: vec!["tcp".to_string()],
            reusable_by: vec!["soap".to_string(), "rest".to_string(), "webhook".to_string()],
        },
        TransportTechnology {
            name: "grpc".to_string(),
            layer: TransportTechnologyLayer::Application,
            built_on: vec!["http".to_string()],
            reusable_by: Vec::new(),
        },
    ]
}

pub fn depends_on(technology: &str, dependency: &str) -> bool {
    core_transport_tree()
        .iter()
        .find(|item| item.name == technology)
        .map(|item| item.built_on.iter().any(|base| base == dependency))
        .unwrap_or(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tcp_and_udp_are_built_on_ip() {
        assert!(depends_on("tcp", "ip"));
        assert!(depends_on("udp", "ip"));
    }

    #[test]
    fn grpc_is_built_on_http() {
        assert!(depends_on("grpc", "http"));
    }

    #[test]
    fn hierarchy_stops_at_ip_for_now() {
        let ip = core_transport_tree()
            .into_iter()
            .find(|item| item.name == "ip")
            .expect("ip technology expected");

        assert!(ip.built_on.is_empty());
    }
}
