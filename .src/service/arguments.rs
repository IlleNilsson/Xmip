//! What `xmip-service` was told: every parameter named, none by position.

use xmip_node::Purpose;

pub const USAGE: &str = "usage: xmip-service --configuration <path> [--console] \
     [--purpose test|runtime]\n       \
     xmip-service --configuration <path> --definition\n       \
     xmip-service --configuration <cluster xmip.toml> --node <name> --slice\n       \
     xmip-service --configuration <cluster xmip.toml> --node <name> --cluster <name> \
     --install\n       \
     xmip-service --configuration <path> --uninstall\n\
     example: xmip-service --configuration /opt/xmip/config/xmip-node.toml --console\n\
     example: xmip-service --configuration /opt/xmip/config/xmip.toml --node R1 --slice\n\
     example: xmip-service --configuration /opt/xmip/config/xmip.toml --node R1 \
     --cluster C1 --install\n\
     --slice prints the node's configuration, sliced from its cluster's xmip.toml.\n\
     --install writes a starter xmip.toml where there is none, slices the node's \
     configuration beside it where there is none, makes the node's folders, and \
     registers and starts its service; --uninstall stops and removes the service \
     of the node configured at <path> and deletes nothing. Both need elevation.\n\
     --console runs in a terminal and stops on Ctrl+C; without it the operating \
     system's service manager runs it and stops it.";

/// How this process runs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    /// Under the operating system's service manager.
    Service,
    /// In a terminal, stopped by Ctrl+C.
    Console,
    /// Print what the service manager is told about the node's service.
    Definition,
    /// Print the node's configuration, sliced from its cluster's
    /// `xmip.toml` (ADR-0031, amendment 2026-10-03).
    Slice,
    /// Lay the node out from its cluster's `xmip.toml` and register its
    /// service, as a package installs it (ADR-0015, amendment 2026-10-13).
    Install,
    /// Stop and remove the node's service; nothing else.
    Uninstall,
}

/// The command line, read.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Arguments {
    /// The node configuration's path; the cluster's `xmip.toml` with
    /// `--slice` and `--install`.
    pub configuration: String,
    pub mode: Mode,
    /// What this process declares it is for (ADR-0053): runtime unless its
    /// starter says test.
    pub purpose: Purpose,
    /// The node `--slice` and `--install` act for.
    pub node: Option<String>,
    /// The cluster a starter `xmip.toml` names, with `--install`.
    pub cluster: Option<String>,
}

impl Arguments {
    /// Read `--flag value` pairs and the switches.
    ///
    /// # Errors
    /// A flag this program does not take, one without its value, a purpose
    /// that is not a purpose word, two switches at once, a switch without
    /// the names it needs or a name no switch takes, or no configuration —
    /// each in words.
    pub fn parse(mut args: impl Iterator<Item = String>) -> Result<Self, String> {
        let mut configuration = None;
        let mut switches = Vec::new();
        let mut node = None;
        let mut cluster = None;
        let mut purpose = Purpose::Runtime;

        while let Some(flag) = args.next() {
            let mut value = || {
                args.next()
                    .filter(|value| !value.starts_with("--"))
                    .ok_or_else(|| format!("{flag} needs a value"))
            };
            match flag.as_str() {
                "--configuration" => configuration = Some(value()?),
                "--purpose" => purpose = Purpose::declared(&value()?)?,
                "--node" => node = Some(value()?),
                "--cluster" => cluster = Some(value()?),
                "--console" => switches.push(Mode::Console),
                "--definition" => switches.push(Mode::Definition),
                "--slice" => switches.push(Mode::Slice),
                "--install" => switches.push(Mode::Install),
                "--uninstall" => switches.push(Mode::Uninstall),
                _ => return Err(format!("{flag} is not a parameter of xmip-service")),
            }
        }

        let mode = match switches.as_slice() {
            [] => Mode::Service,
            [mode] => *mode,
            _ => {
                return Err(
                    "--console, --definition, --slice, --install and --uninstall \
                            exclude each other"
                        .into(),
                );
            }
        };
        names(mode, node.as_ref(), cluster.as_ref())?;
        Ok(Self {
            configuration: configuration.ok_or("--configuration names no node configuration")?,
            mode,
            purpose,
            node,
            cluster,
        })
    }
}

/// Whether `mode` was given the names it needs and no other.
fn names(mode: Mode, node: Option<&String>, cluster: Option<&String>) -> Result<(), String> {
    let takes_node = matches!(mode, Mode::Slice | Mode::Install);
    match (mode, node, cluster) {
        (Mode::Slice, None, _) => Err("--slice needs --node, the node it slices for".into()),
        (Mode::Install, None, _) => Err("--install needs --node, the node it installs".into()),
        (Mode::Install, Some(_), None) => {
            Err("--install needs --cluster, the cluster a starter xmip.toml names".into())
        }
        (_, Some(_), _) if !takes_node => {
            Err("--node is the node --slice or --install acts for".into())
        }
        (mode, _, Some(_)) if mode != Mode::Install => {
            Err("--cluster is the cluster --install names".into())
        }
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parsed(line: &str) -> Result<Arguments, String> {
        Arguments::parse(line.split_whitespace().map(String::from))
    }

    #[test]
    fn every_parameter_is_named_and_the_mode_follows_the_switches() {
        let service = parsed("--configuration a.toml").expect("reads");
        assert_eq!(service.mode, Mode::Service);
        assert_eq!(service.configuration, "a.toml");
        assert_eq!(service.purpose, Purpose::Runtime);

        let console = parsed("--console --purpose test --configuration a.toml").expect("reads");
        assert_eq!(
            (console.mode, console.purpose),
            (Mode::Console, Purpose::Test)
        );

        let definition = parsed("--definition --configuration a.toml").expect("reads");
        assert_eq!(definition.mode, Mode::Definition);

        let slice = parsed("--slice --node n --configuration xmip.toml").expect("reads");
        assert_eq!(
            (slice.mode, slice.node.as_deref()),
            (Mode::Slice, Some("n"))
        );

        let install =
            parsed("--install --node n --cluster c --configuration xmip.toml").expect("reads");
        assert_eq!(
            (install.mode, install.cluster.as_deref()),
            (Mode::Install, Some("c"))
        );
        let uninstall = parsed("--uninstall --configuration xmip-node.toml").expect("reads");
        assert_eq!(uninstall.mode, Mode::Uninstall);
    }

    #[test]
    fn what_it_does_not_take_is_refused_in_words() {
        for (line, words) in [
            ("a.toml", "a.toml is not a parameter"),
            ("--configuration", "--configuration needs a value"),
            ("--configuration --console", "--configuration needs a value"),
            ("--console", "names no node configuration"),
            (
                "--configuration a --console --definition",
                "exclude each other",
            ),
            (
                "--configuration a --install --uninstall",
                "exclude each other",
            ),
            ("--configuration a --slice", "--slice needs --node"),
            ("--configuration a --install", "--install needs --node"),
            (
                "--configuration a --install --node n",
                "--install needs --cluster",
            ),
            (
                "--configuration a --uninstall --node n",
                "--node is the node",
            ),
            ("--configuration a --node n", "--node is the node"),
            (
                "--configuration a --slice --node n --cluster c",
                "--cluster is",
            ),
            ("--configuration a --node", "--node needs a value"),
            ("--configuration a --purpose Test", "test"),
        ] {
            let refused = parsed(line).expect_err(line);
            assert!(refused.contains(words), "{line}: {refused}");
        }
    }
}
