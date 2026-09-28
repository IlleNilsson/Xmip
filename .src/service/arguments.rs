//! What `xmip-service` was told: every parameter named, none by position.

use xmip_node::Purpose;

pub const USAGE: &str = "usage: xmip-service --configuration <path> [--console] \
     [--purpose test|runtime]\n       \
     xmip-service --configuration <path> --definition\n\
     example: xmip-service --configuration /opt/xmip/config/xmip-node.toml --console\n\
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
}

impl Arguments {
    /// Read `--flag value` pairs and the two switches.
    ///
    /// # Errors
    /// A flag this program does not take, one without its value, a purpose
    /// that is not a purpose word, both switches at once, or no
    /// configuration — each in words.
    pub fn parse(mut args: impl Iterator<Item = String>) -> Result<Self, String> {
        let mut configuration = None;
        let mut console = false;
        let mut definition = false;
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
                _ => return Err(format!("{flag} is not a parameter of xmip-service")),
            }
        }

        let mode = match (console, definition) {
            (true, true) => return Err("--console and --definition exclude each other".into()),
            (true, false) => Mode::Console,
            (false, true) => Mode::Definition,
            (false, false) => Mode::Service,
        };
        Ok(Self {
            configuration: configuration.ok_or("--configuration names no node configuration")?,
            mode,
            purpose,
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
            ("--configuration a --purpose Test", "test"),
        ] {
            let refused = parsed(line).expect_err(line);
            assert!(refused.contains(words), "{line}: {refused}");
        }
    }
}
