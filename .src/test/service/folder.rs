//! What a test writes into a node's configuration and drops in its folders:
//! once, for every test here that does (`routed.rs`, `failover.rs`,
//! `linked.rs`, `approved.rs`).

use std::path::Path;

/// A path as a configuration names it.
pub(crate) fn named(path: &Path) -> String {
    path.display().to_string().replace('\\', "/")
}

/// `text` as a configuration writes it: a TOML string, quoted and escaped.
pub(crate) fn quoted(text: &str) -> String {
    toml::Value::String(text.to_string()).to_string()
}

/// `text` dropped into `inbox` as `name`, as a Party drops a file: written
/// beside it in `directory` and renamed in, so no receive reads it half
/// written.
pub(crate) fn dropped(directory: &Path, inbox: &Path, name: &str, text: &str) {
    let beside = directory.join(format!("{name}.part"));
    std::fs::write(&beside, text).expect("written");
    std::fs::rename(&beside, inbox.join(name)).expect("dropped");
}
