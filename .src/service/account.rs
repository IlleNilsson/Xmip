//! `--install --account`: the account the node's service runs as, and what
//! it is given (ADR-0015, amendment 2026-10-21). Without it the service
//! runs as the platform's default, LocalSystem or root, as before.
//!
//! The account reads the node's configuration and the folder its operate
//! listener's key is in, and writes its data and its logs — each folder
//! the node's configuration and the installed layout say, never a path of
//! its own. On Windows a virtual account, `NT SERVICE\xmip-<node>`, exists
//! once its service is registered, so it is given its folders after the
//! registration and before the start; on Linux the account is the
//! machine's, and is given them before the unit starts.

use std::path::{Path, PathBuf};

use crate::install::command;

/// What the account may do in a folder.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Access {
    /// Read what is there, as everyone on the machine may already on Linux.
    Reads,
    /// Read what is there and nobody but the administrators besides: the
    /// folder of its private key.
    Keeps,
    /// Read and write.
    Writes,
}

/// A folder the account is given, and what it may do there.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Given {
    pub folder: PathBuf,
    pub access: Access,
}

/// What the account of the node configured at `node_file` is given: its
/// configuration's folder and its key's to read, its data and `logs` beside
/// `config` to write.
///
/// # Errors
/// The configuration does not read.
pub fn given(node_file: &Path) -> Result<Vec<Given>, String> {
    let shown = node_file.display().to_string();
    let (document, _, _) = xmip_runtime::start::read(&shown).map_err(|unread| unread.reason)?;
    let config = node_file.parent().unwrap_or_else(|| Path::new("."));
    let mut given = vec![Given {
        folder: config.to_path_buf(),
        access: Access::Reads,
    }];
    let key = document
        .operate
        .as_ref()
        .and_then(|operate| operate.key.as_deref());
    if let Some(folder) = key.and_then(|key| config.join(key).parent().map(Path::to_path_buf)) {
        given.push(Given {
            folder,
            access: Access::Keeps,
        });
    }
    given.push(Given {
        folder: document.service.data_directory(node_file),
        access: Access::Writes,
    });
    if let Some(root) = config.parent() {
        given.push(Given {
            folder: root.join("logs"),
            access: Access::Writes,
        });
    }
    Ok(given)
}

/// Give `account` each folder of `given`: on Windows an inherited access
/// rule, read or modify; on Linux the folder and what is in it its own.
///
/// # Errors
/// The platform's command refused, in its words.
pub fn give(account: &str, given: &[Given]) -> Result<(), String> {
    for one in given {
        if !one.folder.exists() {
            continue;
        }
        let folder = one.folder.display().to_string();
        if cfg!(windows) {
            let right = if one.access == Access::Writes {
                "M"
            } else {
                "RX"
            };
            let rule = format!("{account}:(OI)(CI){right}");
            command("icacls.exe", &[folder, "/grant".to_string(), rule], &[])?;
        } else if one.access != Access::Reads {
            command(
                "chown",
                &["-R".to_string(), account.to_string(), folder],
                &[],
            )?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_account_reads_the_configuration_and_its_key_and_writes_data_and_logs() {
        let node = xmip_configure::fixture::test_cluster().node(0).name.clone();
        let base = std::env::temp_dir().join(format!("xmip-account-{}", std::process::id()));
        let config = base.join("config");
        std::fs::create_dir_all(&config).expect("makes the layout");
        let file = config.join("xmip-node.toml");
        let cluster = format!(
            "[operate]\nlisten = \"0.0.0.0:7401\"\ncertificate = \"tls/node.pem\"\n\
             key = \"tls/node.key\"\nanchors = \"tls/anchors.pem\"\n\
             [nodes.{node}]\nroles = \"storage\"\n"
        );
        let text = xmip_configure::slice_named(&cluster, &node, "account").expect("slices");
        std::fs::write(&file, text).expect("writes");

        let given = given(&file).expect("reads");
        let folders: Vec<(PathBuf, Access)> = given
            .iter()
            .map(|one| (one.folder.clone(), one.access))
            .collect();
        assert_eq!(folders[0], (config.clone(), Access::Reads));
        assert_eq!(folders[1], (config.join("tls"), Access::Keeps));
        assert_eq!(folders[2].1, Access::Writes, "the data is written");
        assert_eq!(folders[3], (base.join("logs"), Access::Writes));
        std::fs::remove_dir_all(&base).expect("removes what it wrote");
    }
}
