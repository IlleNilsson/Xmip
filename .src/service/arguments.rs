//! What `xmip-service` was told: every parameter named, none by position.

use std::time::Duration;

use xmip_node::Purpose;

pub const USAGE: &str = "usage: xmip-service --configuration <path> [--console] \
     [--purpose test|runtime]\n       \
     xmip-service --configuration <path> --definition\n       \
     xmip-service --configuration <cluster cluster.xmip> --node <name> [--cluster <name>] \
     [--bind <host[:port],...> [--listen] --nodes <name,...>] [--operators <name,...>] \
     [--authority <folder>] --slice\n       \
     xmip-service --configuration <cluster cluster.xmip> --node <name> --cluster <name> \
     [--account <account>] --install\n       \
     xmip-service --configuration <path> --listening\n       \
     xmip-service --configuration <path> --activation\n       \
     xmip-service --configuration <path> --readiness [--within <seconds>]\n       \
     xmip-service --configuration <path> --uninstall\n\
     example: xmip-service --configuration /opt/xmip/config/node.xmip --console\n\
     example: xmip-service --configuration /opt/xmip/config/cluster.xmip --node RX1 \
     --cluster CL1 --slice\n\
     example: xmip-service --configuration /opt/xmip/config/cluster.xmip --node RX1 \
     --cluster CL1 --bind 10.77.0.1 --nodes RX1,TX1,EX1,EX2,DS1 --slice\n\
     example: xmip-service --configuration /opt/xmip/config/cluster.xmip --node RX1 \
     --cluster CL1 --account xmip --install\n\
     example: xmip-service --configuration /opt/xmip/config/node.xmip --listening\n\
     example: xmip-service --configuration /opt/xmip/config/node.xmip --readiness \
     --within 180\n\
     --slice prints the node's configuration, sliced from its cluster's cluster.xmip; \
     --cluster names the cluster where the file names none; --bind places each \
     Receive Location and Send Port the file designs on one of the environment's \
     --nodes and each Work Process on every one serving its stage, refusing work no \
     node satisfies, the Locations over SFTP on the Parties' far ends at each <host>, \
     each the next far end's in the order placed, port 7422 where it names none; \
     --listen has each Receive Location listen over HTTP on its own node instead, \
     a port of its own from 7480, so any far end pushes to it; --operators lists \
     each name, a certificate's subject CN=<person> or an account, among the node's \
     [operate] operators; \
     what --slice prints is signed by the cluster's authority kept in --authority, \
     where it names none in authority/<cluster> of this account's own Xmip folder \
     (%LOCALAPPDATA%\\Xmip on Windows, ~/.local/state/xmip elsewhere), made there \
     where none is kept, never beside cluster.xmip.\n\
     --install, where the node has no configuration yet, writes a starter cluster.xmip \
     where there is none and slices and signs the node's configuration beside it; it \
     makes the node's folders, \
     registers and starts its service, as --account where it is given, and writes \
     cli.toml beside the programs where there is none, so xmip follows the node; --uninstall \
     stops and removes the service of the node configured at <path> and deletes \
     nothing. Both need elevation.\n\
     --listening prints each port the node's configuration listens on, \
     <port>/<protocol> and what listens.\n\
     --activation says, in the node's words, whether the node runs the slice at <path> \
     as its active configuration, and exits 0 only where it does: a correctly signed \
     slice the node cannot start is refused, and the node runs the last one that ran.\n\
     --readiness says, in the node's words, whether the node is ready: it runs the \
     slice at <path> and its Xmip Storage stands Fine, a Storage node the primary or a \
     standby ready and following; it exits 0 only where it is, asking again each time \
     the node publishes until it is or --within seconds are spent, at once without it. \
     A deployment asks it after it restarts a node, before it restarts the next.\n\
     --console runs in a terminal and stops on Ctrl+C, and with --purpose test also at \
     the end of its input, as the test that started it ends it; without it the \
     operating system's service manager runs it and stops it.";

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
    /// `cluster.xmip` (ADR-0031, amendment 2026-10-03).
    Slice,
    /// Lay the node out from its cluster's `cluster.xmip` and register its
    /// service, as a package installs it (ADR-0015, amendment 2026-10-13).
    Install,
    /// Print the ports the node's configuration listens on, which an
    /// environment opens its firewall for (ADR-0015, amendment 2026-10-21).
    Listening,
    /// Say whether the node runs the slice at its configuration's path as
    /// its active configuration (ADR-0031, amendment 2026-11-12).
    Activation,
    /// Say whether the node is ready, waiting for it within a bound where
    /// one is given (ADR-0056, amendment 2026-11-23).
    Readiness,
    /// Stop and remove the node's service; nothing else.
    Uninstall,
}

/// The command line, read.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Arguments {
    /// The node configuration's path; `cluster.xmip` with
    /// `--slice` and `--install`.
    pub configuration: String,
    pub mode: Mode,
    /// What this process declares it is for (ADR-0053): runtime unless its
    /// starter says test.
    pub purpose: Purpose,
    /// The node `--slice` and `--install` act for.
    pub node: Option<String>,
    /// The cluster, with `--install` and `--slice`: the one a starter
    /// `cluster.xmip` names, and the one a cluster's file that names none
    /// runs as (ADR-0028, amendment 2026-10-21).
    pub cluster: Option<String>,
    /// The account the node's service runs as, with `--install`; the
    /// platform's default where it is not given.
    pub account: Option<String>,
    /// The Parties' far ends, with `--slice`, each Location the cluster's
    /// file designs placed on one of [`Self::nodes`] and bound to the far
    /// end of its turn (ADR-0028, amendments 2026-10-22 and 2026-11-22).
    pub bind: Vec<String>,
    /// With `--bind`: each Receive Location listens on its own node, where
    /// any far end pushes to it, rather than fetching from one.
    pub listen: bool,
    /// The nodes the environment has, with `--bind`.
    pub nodes: Vec<String>,
    /// Who operates the environment's nodes, with `--slice`: each listed
    /// among the node's `[operate] operators` (ADR-0009, amendment
    /// 2026-11-07).
    pub operators: Vec<String>,
    /// The folder the cluster's authority is kept in, with `--slice`: the
    /// machine deploying the environment's, never a node's (ADR-0031,
    /// amendment 2026-11-06); this account's own where it names none
    /// (`signed::own_authority`; amendment 2026-11-25).
    pub authority: Option<String>,
    /// How long `--readiness` waits for the node to be ready; none, it
    /// answers at once.
    pub within: Option<Duration>,
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
        let (mut node, mut cluster, mut account) = (None, None, None);
        let (mut bind, mut nodes, mut operators) = (Vec::new(), Vec::new(), Vec::new());
        let (mut authority, mut listen, mut within) = (None, false, None);
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
                "--account" => account = Some(value()?),
                "--bind" => bind = listed(&value()?),
                "--listen" => listen = true,
                "--authority" => authority = Some(value()?),
                "--nodes" => nodes = listed(&value()?),
                "--operators" => operators = listed(&value()?),
                "--within" => within = Some(seconds(&value()?)?),
                "--console" => switches.push(Mode::Console),
                "--definition" => switches.push(Mode::Definition),
                "--slice" => switches.push(Mode::Slice),
                "--install" => switches.push(Mode::Install),
                "--listening" => switches.push(Mode::Listening),
                "--activation" => switches.push(Mode::Activation),
                "--readiness" => switches.push(Mode::Readiness),
                "--uninstall" => switches.push(Mode::Uninstall),
                _ => return Err(format!("{flag} is not a parameter of xmip-service")),
            }
        }

        let mode = match switches.as_slice() {
            [] => Mode::Service,
            [mode] => *mode,
            _ => {
                return Err(
                    "--console, --definition, --slice, --install, --listening, --activation, \
                     --readiness and --uninstall exclude each other"
                        .into(),
                );
            }
        };
        names(mode, node.as_ref(), cluster.as_ref())?;
        if account.is_some() && mode != Mode::Install {
            return Err("--account is the account --install registers the service as".into());
        }
        placing(mode, &bind, &nodes)?;
        if listen && bind.is_empty() {
            return Err("--listen has the Receive Locations --bind places listen".into());
        }
        if authority.is_some() && mode != Mode::Slice {
            return Err(
                "--authority is the folder --slice signs with the cluster's authority from".into(),
            );
        }
        if !operators.is_empty() && mode != Mode::Slice {
            return Err("--operators are listed in the node's configuration --slice prints".into());
        }
        if within.is_some() && mode != Mode::Readiness {
            return Err("--within is how long --readiness waits for the node".into());
        }
        Ok(Self {
            configuration: configuration.ok_or("--configuration names no node configuration")?,
            mode,
            purpose,
            node,
            cluster,
            account,
            bind,
            listen,
            nodes,
            operators,
            authority,
            within,
        })
    }
}

/// `value`, whole seconds.
fn seconds(value: &str) -> Result<Duration, String> {
    value
        .parse::<u64>()
        .map(Duration::from_secs)
        .map_err(|_| format!("--within takes whole seconds, not '{value}'"))
}

/// The names of a comma-separated list, each trimmed, none empty.
fn listed(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(str::trim)
        .filter(|name| !name.is_empty())
        .map(String::from)
        .collect()
}

/// Whether `mode` was given the names it needs and no other.
fn names(mode: Mode, node: Option<&String>, cluster: Option<&String>) -> Result<(), String> {
    let takes_node = matches!(mode, Mode::Slice | Mode::Install);
    match (mode, node, cluster) {
        (Mode::Slice, None, _) => Err("--slice needs --node, the node it slices for".into()),
        (Mode::Install, None, _) => Err("--install needs --node, the node it installs".into()),
        (Mode::Install, Some(_), None) => {
            Err("--install needs --cluster, the cluster a starter cluster.xmip names".into())
        }
        (_, Some(_), _) if !takes_node => {
            Err("--node is the node --slice or --install acts for".into())
        }
        (_, _, Some(_)) if !takes_node => {
            Err("--cluster is the cluster --slice or --install names".into())
        }
        _ => Ok(()),
    }
}

/// Whether `--bind` and `--nodes` come together, and only with `--slice`.
fn placing(mode: Mode, bind: &[String], nodes: &[String]) -> Result<(), String> {
    match (bind.is_empty(), nodes.is_empty()) {
        (true, true) => Ok(()),
        _ if mode != Mode::Slice => {
            Err("--bind and --nodes place the Locations --slice prints".into())
        }
        (false, false) => Ok(()),
        (false, true) => Err("--bind needs --nodes, the nodes the environment has".into()),
        (true, false) => Err("--nodes needs --bind, the Parties' far end".into()),
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
        let service = parsed("--configuration a.xmip").expect("reads");
        assert_eq!(service.mode, Mode::Service);
        assert_eq!(service.configuration, "a.xmip");
        assert_eq!(service.purpose, Purpose::Runtime);

        let console = parsed("--console --purpose test --configuration a.xmip").expect("reads");
        assert_eq!(
            (console.mode, console.purpose),
            (Mode::Console, Purpose::Test)
        );

        let definition = parsed("--definition --configuration a.xmip").expect("reads");
        assert_eq!(definition.mode, Mode::Definition);

        let slice = parsed("--slice --node n --configuration cluster.xmip").expect("reads");
        assert_eq!(
            (slice.mode, slice.node.as_deref()),
            (Mode::Slice, Some("n"))
        );
        let operated = parsed("--slice --node n --operators CN=a,,CN=b --configuration c.xmip")
            .expect("reads");
        assert_eq!(operated.operators, ["CN=a", "CN=b"]);

        let install =
            parsed("--install --node n --cluster c --configuration cluster.xmip").expect("reads");
        assert_eq!(
            (install.mode, install.cluster.as_deref()),
            (Mode::Install, Some("c"))
        );
        let named =
            parsed("--slice --node n --cluster c --configuration cluster.xmip").expect("reads");
        assert_eq!(
            named.cluster.as_deref(),
            Some("c"),
            "--slice names the cluster"
        );

        let account = "--install --node n --cluster c --account xmip --configuration cluster.xmip";
        assert_eq!(
            parsed(account).expect("reads").account.as_deref(),
            Some("xmip")
        );

        let placed = parsed("--slice --node n --bind h --nodes n,m --configuration cluster.xmip")
            .expect("reads");
        assert_eq!(
            (
                placed.bind.as_slice(),
                placed.nodes.as_slice(),
                placed.listen
            ),
            (
                ["h".to_string()].as_slice(),
                ["n".to_string(), "m".to_string()].as_slice(),
                false
            )
        );
        let pushed = parsed(
            "--slice --node n --bind a,b,c --listen --nodes n,m --configuration cluster.xmip",
        )
        .expect("reads");
        assert_eq!(pushed.bind, ["a", "b", "c"]);
        assert!(pushed.listen);

        let signing = parsed("--slice --node n --authority keep --configuration cluster.xmip")
            .expect("reads");
        assert_eq!(signing.authority.as_deref(), Some("keep"));

        let listening = parsed("--listening --configuration node.xmip").expect("reads");
        assert_eq!(listening.mode, Mode::Listening);

        let activation = parsed("--activation --configuration node.xmip").expect("reads");
        assert_eq!(activation.mode, Mode::Activation);

        let readiness = parsed("--readiness --configuration node.xmip").expect("reads");
        assert_eq!((readiness.mode, readiness.within), (Mode::Readiness, None));
        let waited = parsed("--readiness --within 180 --configuration node.xmip").expect("reads");
        assert_eq!(waited.within, Some(Duration::from_secs(180)));

        let uninstall = parsed("--uninstall --configuration node.xmip").expect("reads");
        assert_eq!(uninstall.mode, Mode::Uninstall);
    }

    #[test]
    fn what_it_does_not_take_is_refused_in_words() {
        for (line, words) in [
            ("a.xmip", "a.xmip is not a parameter"),
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
            ("--configuration a --definition --cluster c", "--cluster is"),
            (
                "--configuration a --slice --node n --account xmip",
                "--account is",
            ),
            (
                "--configuration a --listening --slice",
                "exclude each other",
            ),
            (
                "--configuration a --activation --console",
                "exclude each other",
            ),
            (
                "--configuration a --activation --node n",
                "--node is the node",
            ),
            ("--configuration a --node", "--node needs a value"),
            (
                "--configuration a --slice --node n --bind h",
                "--bind needs --nodes",
            ),
            (
                "--configuration a --slice --node n --nodes n",
                "--nodes needs --bind",
            ),
            (
                "--configuration a --listening --bind h --nodes n",
                "place the Locations --slice prints",
            ),
            (
                "--configuration a --slice --node n --listen",
                "--listen has the Receive Locations --bind places listen",
            ),
            (
                "--configuration a --install --node n --cluster c --authority k",
                "--authority is the folder --slice signs",
            ),
            (
                "--configuration a --install --node n --cluster c --operators CN=o",
                "--operators are listed in the node's configuration --slice prints",
            ),
            ("--configuration a --purpose Test", "test"),
            (
                "--configuration a --readiness --activation",
                "exclude each other",
            ),
            (
                "--configuration a --activation --within 5",
                "--within is how long --readiness waits",
            ),
            (
                "--configuration a --readiness --within soon",
                "--within takes whole seconds, not 'soon'",
            ),
            (
                "--configuration a --readiness --within",
                "--within needs a value",
            ),
        ] {
            let refused = parsed(line).expect_err(line);
            assert!(refused.contains(words), "{line}: {refused}");
        }
    }
}
