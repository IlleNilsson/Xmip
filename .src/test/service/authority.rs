//! The assembled service serves the cluster's authority, the premises' own
//! ACME service (ADR-0034, amendment 2026-10-22): a node whose
//! `[provision.node]` names `internal-ca` and `serve` answers ACME there
//! and publishes its revocation list over plain HTTP, `--listening` says
//! both ports, and a client on the premises obtains a certificate from it,
//! is told when to renew it and revokes it into the list, while the node
//! runs; the authority is kept beside the configuration.

use std::io::{BufReader as Reading, Write};

use xmip_provision_acme::{Challenge, Channel, Client};

use super::*;

/// The node's configuration in `directory`, serving the authority on
/// `serve` and publishing on `publish`, asking http-01 on `challenge`.
fn serving(directory: &Path, serve: &str, publish: &str, challenge: u16) -> PathBuf {
    let configuration = written(directory, "");
    let text = std::fs::read_to_string(&configuration).expect("reads");
    let table = format!(
        "\n[provision.node]\nsource = \"xmip-core-provision-internal-ca\"\n\
         names = \"localhost\"\nlifetime = \"2160h\"\nauthority_lifetime = \"87600h\"\n\
         serve = \"{serve}\"\npublish = \"{publish}\"\n\
         published_at = \"http://{publish}\"\nchallenge_port = {challenge}\n\n[operate]"
    );
    std::fs::write(&configuration, text.replacen("\n[operate]", &table, 1)).expect("writes");
    configuration
}

#[test]
fn the_service_answers_acme_for_the_premises_and_publishes_its_list() {
    let _machine = sharing();
    let directory =
        std::env::temp_dir().join(format!("xmip-service-authority-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    // Where `localhost` resolves first, which every connection to it tries
    // first: listening there, nothing waits on the refusal of another.
    let first = std::net::ToSocketAddrs::to_socket_addrs(&("localhost", 0))
        .expect("localhost resolves")
        .next()
        .expect("to an address")
        .ip();
    let on = || xmip_net::fixture::unheld_on(first);
    let (serve, publish, challenge) = (on(), on(), on());
    let configuration = serving(
        &directory,
        &serve.to_string(),
        &publish.to_string(),
        challenge.port(),
    );

    let listening = Command::new(env!("CARGO_BIN_EXE_xmip-service"))
        .args([
            "--configuration",
            configuration.to_str().expect("UTF-8"),
            "--listening",
        ])
        .output()
        .expect("asked");
    let said = String::from_utf8_lossy(&listening.stdout);
    assert!(said.contains(&format!("{}/tcp", serve.port())), "{said}");
    assert!(said.contains(&format!("{}/tcp", publish.port())), "{said}");

    let mut child = spawned(&configuration, &directory);
    let _ending = Ending(Some(child.id()));
    let lines = lines(&mut child);
    let answers = heard(&lines, "answers ACME at ", Duration::from_secs(30));
    let at = answers
        .split("answers ACME at ")
        .nth(1)
        .expect("a directory");
    let directory_url = at.split_whitespace().next().expect("a URL").to_string();
    heard(&lines, "accepts work", Duration::from_secs(30));

    let anchor = std::fs::read_to_string(directory.join("authority").join("authority.pem"))
        .expect("the authority is kept beside the configuration");
    let channel = Channel::new(Some(&anchor), Duration::from_secs(5)).expect("a channel");
    let key = xmip_provision::KeyPair::generate().expect("an account key");
    let client = Client::open(channel, &directory_url, key, None, true).expect("an account");
    let answer = Challenge::Http01 {
        listen: challenge.to_string(),
    };
    let (chain, _) = client
        .certificate(&["localhost".to_string()], &answer, Duration::from_secs(10))
        .expect("issued by the node's authority");
    assert!(client.renewal_window(&chain).expect("asked").is_some());
    client.revoke(&chain, 1).expect("revoked");

    let tcp = std::net::TcpStream::connect(publish).expect("the publication");
    let mut writer = tcp.try_clone().expect("clone");
    let request = xmip_net::http::Request::new("GET", "/crl").header("Host", "localhost");
    xmip_net::http::write_request(&mut writer, &request).expect("asked");
    writer.flush().expect("flushed");
    let listed = xmip_net::http::read_response(&mut Reading::new(tcp)).expect("answered");
    let list = xmip_provision::crl::read(&listed.body).expect("a revocation list");
    let leaf = xmip_provision::Parsed::first(&chain).expect("the leaf");
    assert!(
        list.names(&leaf.serial).is_some(),
        "revoked into the list the node publishes"
    );

    stop(&child);
    assert!(exited(child, Duration::from_secs(30)).success());
    let _ = std::fs::remove_dir_all(&directory);
}
