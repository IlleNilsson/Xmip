//! A stop drains the node and the service exits 0; what it cannot start is
//! refused with exit 2; a paused Subscription outlives a restart.

use super::*;

#[test]
fn a_stop_drains_the_node_and_the_service_exits_zero() {
    let directory = std::env::temp_dir().join(format!("xmip-service-stop-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let receive = free_address();
    let configuration = written(&directory, &receive);

    let mut child = spawned(&configuration, &directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        "xmip:///C1/node/R1 accepts work",
        Duration::from_secs(10),
    );

    let declared = declarations(&directory);
    assert!(
        declared
            .iter()
            .any(|text| text.contains("location = \"xmip:///C1/node/R1\"")
                && text.contains("purpose = \"test\"")),
        "{declared:?}"
    );

    for message in 0..MESSAGES {
        deliver(&receive, format!("order {message}").as_bytes());
    }

    stop(&child);
    let asked = Instant::now();
    let stopped = heard(&said, "stopped by the console", Duration::from_secs(5));
    let status = exited(child, Duration::from_secs(5));
    let took = asked.elapsed();
    ending.0 = None;

    assert!(status.success(), "{status}");
    // The Location's own wait, a tenth of a second, bounds the drain.
    assert!(took < Duration::from_secs(2), "stopping took {took:?}");
    assert!(
        stopped.contains(&format!("received {MESSAGES}")),
        "{stopped}"
    );
    assert!(
        stopped.contains(&format!("refused {MESSAGES}")),
        "{stopped}"
    );
    assert!(
        declarations(&directory).is_empty(),
        "the declaration goes with it"
    );

    let audit =
        std::fs::read_to_string(directory.join("audit").join("audit.toml")).expect("it audited");
    for said in [
        "action = \"start\"",
        "action = \"stop\"",
        "\"by\" = \"the console\"",
        &format!("\"received\" = \"{MESSAGES}\""),
    ] {
        assert!(audit.contains(said), "{said} in {audit}");
    }
    let _ = std::fs::remove_dir_all(&directory);
}

#[test]
fn a_node_it_cannot_start_is_refused_with_exit_code_two() {
    let directory =
        std::env::temp_dir().join(format!("xmip-service-refused-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let configuration = written(&directory, &free_address());
    let text = std::fs::read_to_string(&configuration).expect("reads");
    std::fs::write(
        &configuration,
        text.replacen("xmip-core-transport-tcp", "xmip-core-transport-sftp", 1),
    )
    .expect("writes");

    let output = Command::new(env!("CARGO_BIN_EXE_xmip-service"))
        .args([
            "--configuration",
            configuration.to_str().expect("UTF-8"),
            "--console",
        ])
        .env("XMIP_AUDIT_DIRECTORY", directory.join("audit"))
        .env("XMIP_PROCESS_DIRECTORY", directory.join("process"))
        .output()
        .expect("runs");

    assert_eq!(output.status.code(), Some(2));
    let said = String::from_utf8_lossy(&output.stderr);
    assert!(said.contains("xmip-core-transport-sftp"), "{said}");
    assert!(declarations(&directory).is_empty());
    let _ = std::fs::remove_dir_all(&directory);
}

/// Start the service at `configuration`, act on its Subscription as each
/// of `acts` says, hearing each answer, and stop it the operating system's
/// way.
fn served(configuration: &Path, directory: &Path, acts: &[(Act, &str)]) {
    let mut child = spawned(configuration, directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        "keeps its store xmip-core-persist-rocksdb",
        Duration::from_secs(10),
    );
    heard(
        &said,
        &format!("{NODE} accepts work"),
        Duration::from_secs(10),
    );
    for (act, answer) in acts {
        order(directory, *act);
        heard(&said, answer, Duration::from_secs(2));
    }
    stop(&child);
    heard(&said, "stopped by the console", Duration::from_secs(5));
    assert!(exited(child, Duration::from_secs(5)).success());
    ending.0 = None;
}

#[test]
fn a_paused_subscription_is_paused_still_after_the_service_restarts() {
    let directory = std::env::temp_dir().join(format!("xmip-service-store-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let configuration = written(&directory, &free_address());

    served(
        &configuration,
        &directory,
        &[(Act::Pause, "Subscription 'onward' paused by C1-operator")],
    );
    assert!(
        directory.join("data").join("persistence-rocksdb").is_dir(),
        "the store is where the layout puts it"
    );
    served(
        &configuration,
        &directory,
        &[
            (Act::Pause, "Subscription 'onward' was already paused"),
            (
                Act::Resume,
                "Subscription 'onward' resumed by C1-operator; the 0 it held",
            ),
        ],
    );

    let audit =
        std::fs::read_to_string(directory.join("audit").join("audit.toml")).expect("it audited");
    for said in [
        "subscription.pause",
        "subscription.resume",
        "persistence-rocksdb",
    ] {
        assert!(audit.contains(said), "{said} in {audit}");
    }
    let _ = std::fs::remove_dir_all(&directory);
}

/// What the service says on stderr refusing the node at `configuration`,
/// which must exit 2.
fn refused(configuration: &Path, directory: &Path) -> String {
    let output = Command::new(env!("CARGO_BIN_EXE_xmip-service"))
        .args([
            "--configuration",
            configuration.to_str().expect("UTF-8"),
            "--console",
        ])
        .env("XMIP_AUDIT_DIRECTORY", directory.join("audit"))
        .env("XMIP_PROCESS_DIRECTORY", directory.join("process"))
        .output()
        .expect("runs");
    assert_eq!(output.status.code(), Some(2));
    String::from_utf8_lossy(&output.stderr).into_owned()
}

#[test]
fn a_store_the_build_did_not_link_or_that_does_not_open_is_refused() {
    let directory =
        std::env::temp_dir().join(format!("xmip-service-unstored-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let configuration = written(&directory, &free_address());
    let text = std::fs::read_to_string(&configuration).expect("reads");

    // The engine is no node's choice (ADR-0015, amendment 2026-10-01).
    std::fs::write(
        &configuration,
        format!("{text}\n[store]\nengine = \"xmip-core-persist-lmdb\"\n"),
    )
    .expect("writes");
    let said = refused(&configuration, &directory);
    assert!(said.contains("engine"), "{said}");

    let unlinked = "[store]
key_store = \"xmip-core-secret-vault\"
";
    std::fs::write(
        &configuration,
        format!(
            "{text}
{unlinked}"
        ),
    )
    .expect("writes");
    let said = refused(&configuration, &directory);
    assert!(
        said.contains("'xmip-core-secret-vault', which this node was not built with"),
        "{said}"
    );

    // A file where the engine wants its directory.
    std::fs::write(directory.join("taken"), "not a store").expect("writes");
    std::fs::write(
        &configuration,
        format!(
            "{text}
[store]
place = \"taken\"
"
        ),
    )
    .expect("writes");
    let said = refused(&configuration, &directory);
    assert!(said.contains("did not open"), "{said}");
    assert!(declarations(&directory).is_empty());
    let audit =
        std::fs::read_to_string(directory.join("audit").join("audit.toml")).expect("it audited");
    assert!(audit.contains("xmip-core-secret-vault"), "{audit}");
    let _ = std::fs::remove_dir_all(&directory);
}
