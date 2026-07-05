use serde::{Deserialize, Serialize};
use xmip_configuration::parse_service_configuration;
use xmip_runtime::execution_tree::{
    build_execution_tree, ExecutionTree, StartupValidationReport,
};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum XmipServiceState {
    Created,
    ConfigurationRead,
    ExecutionTreeBuilt,
    StartupValidated,
    ReadyToStartSystemProcesses,
    Running,
    Failed,
}

#[derive(Clone, Debug)]
pub struct XmipServiceStartupPlan {
    pub state: XmipServiceState,
    pub execution_tree: ExecutionTree,
    pub validation_report: StartupValidationReport,
}

pub fn plan_startup_from_toml(source: &str) -> Result<XmipServiceStartupPlan, StartupValidationReport> {
    let configuration = parse_service_configuration(source).map_err(|error| StartupValidationReport {
        errors: vec![format!("configuration parse failed: {error}")],
        warnings: Vec::new(),
    })?;

    let (execution_tree, validation_report) = build_execution_tree(configuration)?;

    Ok(XmipServiceStartupPlan {
        state: XmipServiceState::ReadyToStartSystemProcesses,
        execution_tree,
        validation_report,
    })
}

pub fn startup_sequence() -> Vec<&'static str> {
    vec![
        "read-configuration",
        "build-execution-tree",
        "validate-startup",
        "plan-system-processes",
        "start-system-processes",
        "load-modules",
        "register-capabilities",
        "verify-extensions",
        "accept-work",
    ]
}
