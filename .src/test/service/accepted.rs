//! The assembled service accepts a Stream from a configured Party over a
//! Receive Location that terminates TLS, and refuses, and audits, one whose
//! certificate names any other (open problem 33; ADR-0019 clause 1;
//! ADR-0033, amendment 2026-10-19). Every gate is the build's own
//! technology: tcp terminating TLS with the node's `[provision.receive]`
//! certificate, `certificate` claiming the subject its handshake verified,
//! `mutual-tls` recording that, `[[parties]]` resolving it, the Location's
//! `accept.party` narrowing it, and `location` admitting it.

use std::io::{Read, Write};
use std::path::Path;
use std::sync::Arc;

use xmip_runtime::fixture::Authority;

use super::*;

/// The Party the Location takes, and one it does not: named for the test
/// cluster, so no test names a Party.
fn parties() -> [String; 2] {
    let cluster = &test_cluster().name;
    [format!("{cluster}-accepted"), format!("{cluster}-other")]
}

/// The certificate subject a Party presents.
fn subject(party: &str) -> String {
    format!("{party}.example")
}

/// The node's configuration in `directory`, its Receive Location `In`
/// terminating TLS with the node's `receive` certificate, which the test
/// authority issued and whose anchors are that authority, and taking
/// `mutual-tls` from the first of [`parties`] alone. Its Location waits its
/// tenth of a second per read of content, as every Location here does: the
/// handshake is read under its own bound (`[tuning] receive_handshake`), so
/// a client on a loaded machine whose handshake messages come a tenth
/// apart is not dropped before any gate (the millisecond rule: a longer
/// receive wait was never the fix; 2026-10-20).
fn guarded(directory: &Path, authority: &Authority, receive: &str) -> std::path::PathBuf {
    let configuration = written(directory, receive);
    let (certificate, key, anchors) = authority.pem("localhost");
    for (name, text) in [
        ("receive.pem", &certificate),
        ("receive.key", &key),
        ("parties.pem", &anchors),
    ] {
        std::fs::write(directory.join(name), text).expect("written");
    }
    let [accepted, other] = parties();
    let declared = [&accepted, &other]
        .iter()
        .map(|party| {
            format!(
                "[[parties]]\nid = \"{}\"\nname = \"{party}\"\nidentities = [\
                 {{ mechanism = \"mutual-tls\", purpose = \"receive\", value = \"CN={}\" }}]\n\n",
                xmip_configure::party::mint(),
                subject(party)
            )
        })
        .collect::<Vec<_>>()
        .concat();
    let text = std::fs::read_to_string(&configuration).expect("reads");
    let text = text
        .replacen(
            "[[applications]]",
            &format!("{declared}[[applications]]"),
            1,
        )
        .replacen(
            "timeout = \"100ms\"\n",
            &format!(
                "timeout = \"100ms\"\ntls = true\n\
                 [applications.receive_locations.accept]\n\
                 mechanism = [\"mutual-tls\"]\nparty = [\"{accepted}\"]\n"
            ),
            1,
        )
        .replacen(
            "\n[operate]",
            "\n[provision.receive]\ncertificate = \"receive.pem\"\nkey = \"receive.key\"\n\
             anchors = \"parties.pem\"\n\n[operate]",
            1,
        );
    std::fs::write(&configuration, text).expect("writes");
    configuration
}

/// `client` sends a Stream to `address` in TLS, connecting again while the
/// Location has not yet bound — it binds on its first receive — and reads
/// to the node's close. Bounded, and never a sleep.
fn send(address: &str, client: xmip_tls::ClientConfig) {
    let deadline = Instant::now() + Duration::from_secs(5);
    let tcp = loop {
        match xmip_transport::socket::connect_tcp(address, Some(Duration::from_secs(5))) {
            Ok(tcp) => break tcp,
            Err(_) if Instant::now() < deadline => std::thread::yield_now(),
            Err(failed) => panic!("the node took nothing at {address}: {failed:?}"),
        }
    };
    let Ok(mut stream) = xmip_tls::client_with("localhost", tcp, Arc::new(client)) else {
        return;
    };
    let _ = stream.write_all(b"<order/>");
    stream.conn.send_close_notify();
    let _ = stream.flush();
    let _ = stream.read_to_end(&mut Vec::new());
}

#[test]
fn a_configured_party_is_accepted_over_tls_and_another_refused_and_audited() {
    let directory =
        std::env::temp_dir().join(format!("xmip-service-accepted-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&directory);
    let authority = Authority::new();
    let receive = unheld().to_string();
    let configuration = guarded(&directory, &authority, &receive);

    let mut child = spawned(&configuration, &directory);
    let mut ending = Ending(Some(child.id()));
    let said = lines(&mut child);
    heard(
        &said,
        &format!("{} accepts work", node_scope()),
        Duration::from_secs(10),
    );

    let [accepted, other] = parties();
    for party in [&accepted, &other] {
        let client = authority.identity(&subject(party)).client();
        send(&receive, client.expect("a client"));
    }
    // Issued by nobody the node trusts: refused in the handshake, before
    // any gate, so never received.
    let stranger = Authority::new().identity(&subject(&accepted)).client();
    send(&receive, stranger.expect("a client"));

    stop(&child);
    let stopped = heard(&said, "stopped by the console", Duration::from_secs(5));
    assert!(exited(child, Duration::from_secs(5)).success());
    ending.0 = None;

    assert!(stopped.contains("received 2"), "{stopped}");
    assert!(stopped.contains("refused 1"), "{stopped}");
    let audit =
        std::fs::read_to_string(directory.join("audit").join("audit.toml")).expect("it audited");
    for said in [
        "\"xmip.transport.mechanism\" = \"mutual-tls\"",
        &format!("\"xmip.transport.identity\" = \"CN={}\"", subject(&other)),
        "\"xmip.transport.established\" = \"passed\"",
        "which this location does not take",
    ] {
        assert!(audit.contains(said), "{said} in {audit}");
    }
    let _ = std::fs::remove_dir_all(&directory);
}
