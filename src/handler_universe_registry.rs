use crate::handler_universe::HandlerRepository;
use crate::handler_universe_business::BUSINESS_HANDLER_REPOSITORIES;
use crate::handler_universe_enterprise::ENTERPRISE_HANDLER_REPOSITORIES;
use crate::handler_universe_industrial::INDUSTRIAL_HANDLER_REPOSITORIES;
use crate::handler_universe_network::NETWORK_HANDLER_REPOSITORIES;

pub fn all_handler_repositories() -> Vec<&'static HandlerRepository> {
    let mut repositories = Vec::new();
    repositories.extend(NETWORK_HANDLER_REPOSITORIES.iter());
    repositories.extend(BUSINESS_HANDLER_REPOSITORIES.iter());
    repositories.extend(INDUSTRIAL_HANDLER_REPOSITORIES.iter());
    repositories.extend(ENTERPRISE_HANDLER_REPOSITORIES.iter());
    repositories
}

pub fn find_handler_repository(repository_name: &str) -> Option<&'static HandlerRepository> {
    all_handler_repositories()
        .into_iter()
        .find(|repository| repository.repository_name == repository_name)
}

pub fn repositories_for_space(
    space: crate::handler_universe::HandlerSpace,
) -> Vec<&'static HandlerRepository> {
    all_handler_repositories()
        .into_iter()
        .filter(|repository| repository.space == space)
        .collect()
}

pub fn validate_handler_universe() -> Result<(), String> {
    let repositories = all_handler_repositories();

    if repositories.is_empty() {
        return Err("handler universe is empty".to_string());
    }

    let mut repository_names = std::collections::HashSet::new();
    let mut submodule_paths = std::collections::HashSet::new();

    for repository in repositories {
        validate_repository_name(repository.repository_name)?;
        validate_submodule_path(repository.submodule_path)?;

        if !repository_names.insert(repository.repository_name) {
            return Err(format!("duplicate handler repository name: {}", repository.repository_name));
        }

        if !submodule_paths.insert(repository.submodule_path) {
            return Err(format!("duplicate handler submodule path: {}", repository.submodule_path));
        }
    }

    Ok(())
}

fn validate_repository_name(repository_name: &str) -> Result<(), String> {
    if !repository_name.starts_with("xmip-handler-") {
        return Err(format!("handler repository does not follow ADR-0001: {}", repository_name));
    }

    if repository_name.ends_with('-') || repository_name.contains("--") {
        return Err(format!("invalid handler repository spelling: {}", repository_name));
    }

    if !repository_name
        .chars()
        .all(|character| character.is_ascii_lowercase() || character.is_ascii_digit() || character == '-')
    {
        return Err(format!("handler repository must be lowercase kebab-case: {}", repository_name));
    }

    Ok(())
}

fn validate_submodule_path(submodule_path: &str) -> Result<(), String> {
    if !(submodule_path.starts_with("handlers/") || submodule_path.starts_with("runtime/")) {
        return Err(format!("submodule path must start with handlers/ or runtime/: {}", submodule_path));
    }

    if submodule_path.ends_with('/') || submodule_path.contains("//") {
        return Err(format!("invalid submodule path: {}", submodule_path));
    }

    Ok(())
}
