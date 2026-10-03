//! What `xmip-service` was told: every parameter named, none by position.

use xmip_node::Purpose;

pub const USAGE: &str = "usage: xmip-service --configuration <path> [--console] \
     [--purpose test|runtime]\n       \
     xmip-service --configuration <path> --definition\n       \
     xmip-service --configuration <cluster xmip.toml> --node <name> --slice\n\
     example: xmip-service --configuration /opt/xmip/config/xmip-node.toml --console\n\
     example: xmip-service --configuration /opt/xmip/config/xmip.toml --node R1 --slice\n\
     --slice prints the node's configuration, sliced from its cluster's xmip.toml.\n\
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
}

/// The command line, read.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Arguments {
    /// The node configuration's path.
    pub configuration: String,
    pub mode: Mode,
    /// What this process declares it is for (ADR-0053): runtime unless its
    /// starter says test.
    pub purpose: Purpose,
    /// The node a cluster's `xmip.toml` is sliced for, with `--slice`.
    pub node: Option<String>,
}

impl Arguments {
    /// Read `--flag value` pairs and the three switches.
    ///
    /// # Errors
    /// A flag this program does not take, one without its value, a purpose
    /// that is not a purpose word, two switches at once, `--slice` without
    /// `--node` or `--node` without `--slice`, or no configuration — each in
    /// words.
    pub fn parse(mut args: impl Iterator<Item = String>) -> Result<Self, String> {
        let mut configuration = None;
        let mut console = false;
        let mut definition = false;
        let mut slice = false;
        let mut node = None;
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
                "--console" => console = true,
                "--definition" => definition = true,
                "--slice" => slice = true,
                "--node" => node = Some(value()?),
                _ => return Err(format!("{flag} is not a parameter of xmip-service")),
            }
        }

        let mode = match (console, definition, slice) {
            (true, false, false) => Mode::Console,
            (false, true, false) => Mode::Definition,
            (false, false, true) => Mode::Slice,
            (false, false, false) => Mode::Service,
            _ => return Err("--console, --definition and --slice exclude each other".into()),
        };
        match (mode, &node) {
            (Mode::Slice, None) => {
                return Err("--slice needs --node, the node it slices for".into());
            }
            (Mode::Slice, Some(_)) | (_, None) => {}
            (_, Some(_)) => return Err("--node is the node --slice slices for".into()),
        }
        Ok(Self {
            configuration: configuration.ok_or("--configuration names no node configuration")?,
            mode,
            purpose,
            node,
        })
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
            ("--configuration a --slice", "--slice needs --node"),
            ("--configuration a --node n", "--node is the node --slice"),
            ("--configuration a --node", "--node needs a value"),
            ("--configuration a --purpose Test", "test"),
        ] {
            let refused = parsed(line).expect_err(line);
            assert!(refused.contains(words), "{line}: {refused}");
        }
    }
}
