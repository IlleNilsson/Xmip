//! A node reaching Storage node processes over mutual TLS through Xmip's
//! own TLS (ADR-0063, amendment 2026-10-01), round robin, one of them
//! killed; the audit keeper over the real engines; and what a write costs,
//! measured idle (`runtime-model.md` section 3, *What proves it*: *the
//! sync's latency measured idle and under load, and reported*).
//!
//! Each Storage node process here keeps a database of its own, so what one
//! was told the other was not: round robin over embedded Storage nodes
//! carries the work on, and only Storage nodes in front of one database
//! server (option A) share what they keep — which `xmip-core-persist`'s own
//! tests prove with two servers over one database.

use std::net::TcpListener;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use xmip_core::AuditId;
use xmip_persist::storage::client::PASS_OVER;
use xmip_persist::storage::{
    AuditBody, AuditEntry, Audited, ChunkReader, Form, StorageClient, StorageServer, StreamChunk,
    StreamDigest, StreamRecord, XmipStorage,
};
use xmip_persist_sqlite::Sqlite;
use xmip_runtime::ledger::CHUNK;

use super::{
    TestNode, directory, heard, journey, percentiles, spawn, test_node, test_node_over, timed,
};

/// Each connect and each read a node makes of a Storage node.
const TIMEOUT: Duration = Duration::from_secs(10);

/// The authority's certificate, the same every time it is made from the
/// same key: what a leaf names as its issuer and what an anchor holds.
fn authority_params() -> rcgen::CertificateParams {
    let mut params = rcgen::CertificateParams::new(Vec::<String>::new()).expect("params");
    params.is_ca = rcgen::IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
    params
}

/// The cluster's certificate authority in a test's directory, made once
/// by the test before any child starts: its certificate and its key, PEM.
pub fn authority(place: &Path) {
    let key = rcgen::KeyPair::generate().expect("a key");
    let cert = authority_params().self_signed(&key).expect("signed");
    std::fs::write(place.join("authority.pem"), cert.pem()).expect("written");
    std::fs::write(place.join("authority-key.pem"), key.serialize_pem()).expect("written");
}

/// An identity the authority in `place` issues to a node at 127.0.0.1.
fn issue(place: &Path) -> xmip_tls::Identity {
    let authority_pem = std::fs::read_to_string(place.join("authority.pem")).expect("read");
    let authority_key = std::fs::read_to_string(place.join("authority-key.pem")).expect("read");
    let authority_key = rcgen::KeyPair::from_pem(&authority_key).expect("the authority's key");
    let issuer = authority_params()
        .self_signed(&authority_key)
        .expect("the authority again");
    let key = rcgen::KeyPair::generate().expect("a key");
    let leaf = rcgen::CertificateParams::new(vec!["127.0.0.1".to_string()])
        .expect("params")
        .signed_by(&key, &issuer, &authority_key)
        .expect("issued");
    xmip_tls::Identity::from_pem(
        leaf.pem().as_bytes(),
        key.serialize_pem().as_bytes(),
        authority_pem.as_bytes(),
    )
    .expect("an identity")
}

/// `node` served on a port of its own, presenting an identity the
/// authority in `place` issued.
pub fn serve(node: Arc<TestNode>, place: &Path) -> StorageServer {
    let authority = place.parent().expect("the test's directory");
    let listener = TcpListener::bind("127.0.0.1:0").expect("bound");
    StorageServer::start(node, listener, &issue(authority)).expect("served")
}

#[test]
fn a_node_reaches_storage_over_tls_and_carries_on_past_a_killed_storage_node() {
    let test = directory("served");
    authority(&test);
    let (first, second) = (test.join("first"), test.join("second"));
    let (mut one, one_says) = spawn("serve", &first);
    let (mut two, two_says) = spawn("serve", &second);
    let addresses = [
        heard(&one_says, "serving ", Duration::from_secs(60)),
        heard(&two_says, "serving ", Duration::from_secs(60)),
    ];
    let client =
        StorageClient::new(&addresses, &issue(&test), TIMEOUT, PASS_OVER).expect("a client");
    for number in 0..10 {
        client
            .write_journey(&xmip_persist::storage::JourneyRecord {
                journey: journey(number),
                body: b"before".to_vec(),
                facts: xmip_persist::storage::JourneyFacts::default(),
            })
            .expect("written");
    }
    one.kill().expect("killed");
    let _ = one.wait();
    for number in 10..20 {
        client
            .write_journey(&xmip_persist::storage::JourneyRecord {
                journey: journey(number),
                body: b"after".to_vec(),
                facts: xmip_persist::storage::JourneyFacts::default(),
            })
            .expect("carried on through the other Storage node");
        let read = client.read_journey(journey(number)).expect("read");
        assert_eq!(read.map(|record| record.body), Some(b"after".to_vec()));
    }
    drop(two.stdin.take());
    assert!(
        two.wait().expect("stopped").success(),
        "the Storage node stopped cleanly"
    );
    let _ = std::fs::remove_dir_all(&test);
}

#[test]
fn the_audit_keeper_moves_each_record_once_over_the_real_engines() {
    let place = directory("keeper");
    // The audit database elsewhere: a file of its own, apart from the
    // administration database's (ADR-0070, amendment 2026-10-10).
    std::fs::create_dir_all(place.join("elsewhere")).expect("its directory");
    let (administration, audit) = (
        place.join("administration.sqlite"),
        place.join("elsewhere").join("audit.sqlite"),
    );
    let opened = |file: &Path| Sqlite::open(file).expect("a database");
    let node = test_node_over(&place, opened(&administration), opened(&audit));
    let entries: Vec<AuditEntry> = (1..=100u128)
        .map(|id| AuditEntry {
            id: AuditId::new(0x0199_0000_0000_7000_a000_0000_0000_0000 | id),
            body: format!("audited {id}").into_bytes(),
            audited: None,
            facts: xmip_persist::storage::AuditFacts::default(),
        })
        .collect();
    for entry in &entries {
        node.write_audit(entry).expect("written");
    }
    node.write_audit(&entries[7]).expect("written twice");
    assert_eq!(node.keep_audit(60, CHUNK).expect("kept"), 60);
    assert_eq!(node.keep_audit(60, CHUNK).expect("kept"), 41);
    assert_eq!(node.keep_audit(60, CHUNK).expect("kept"), 0);
    for entry in &entries {
        assert_eq!(body(&node, entry.id).body, entry.body);
    }
    drop(node);
    // Kept in the audit database's file, and nothing of it in the
    // administration database's: read as an audit database, it holds none.
    let memory = || Sqlite::in_memory().expect("a database");
    let reopened = test_node_over(&place, memory(), opened(&audit));
    for entry in &entries {
        let kept = reopened.read_kept_audit(entry.id).expect("read");
        assert!(kept.is_some(), "kept in the audit database");
    }
    drop(reopened);
    let administration = test_node_over(&place, memory(), opened(&administration));
    for entry in &entries {
        let there = administration.read_kept_audit(entry.id).expect("read");
        assert_eq!(there, None, "nothing audit in the administration database");
    }
    drop(administration);
    let _ = std::fs::remove_dir_all(&place);
}

/// The body of the kept audit record `id`, read back from its chunks and
/// held to its length and digest (ADR-0070, amendment 2026-10-10).
fn body(node: &TestNode, id: AuditId) -> AuditBody {
    let mut read = Vec::new();
    std::io::Read::read_to_end(
        &mut ChunkReader::audit_body(node, id)
            .expect("read")
            .expect("kept"),
        &mut read,
    )
    .expect("its body as kept");
    AuditBody::from_bytes(&read).expect("a body")
}

/// A Stream of three chunks an audit record carries, kept beside the record
/// by the keeper over the real engines and read back verified (ADR-0070).
#[test]
fn an_audited_stream_is_kept_beside_its_record_over_the_real_engines() {
    let place = directory("audited");
    let node = test_node(&place);
    let stream = xmip_core::StreamId::new(0x0199_0000_0000_7000_b000_0000_0000_0001);
    let content: Vec<u8> = (0..10_000u32).flat_map(u32::to_be_bytes).collect();
    let mut digest = StreamDigest::default();
    let pieces: Vec<&[u8]> = content.chunks(16_384).collect();
    for (index, bytes) in (0..).zip(&pieces) {
        digest.update(bytes);
        let chunk = StreamChunk {
            stream,
            index,
            bytes: bytes.to_vec(),
        };
        if index + 1 < 3 {
            node.write_chunk(&chunk).expect("written");
        } else {
            let record = StreamRecord {
                stream,
                length: content.len() as u64,
                chunks: 3,
                digest: digest.clone().finish(),
                written_unix_nanos: 0,
            };
            node.write_stream(&chunk, &record).expect("written");
        }
    }
    let id = AuditId::new(0x0199_0000_0000_7000_b000_0000_0000_0002);
    let entry = AuditEntry {
        id,
        body: b"audited".to_vec(),
        audited: Some(Audited {
            message: b"the Message".to_vec(),
            streams: vec![stream],
        }),
        facts: xmip_persist::storage::AuditFacts::default(),
    };
    node.write_audit(&entry).expect("written");
    assert_eq!(node.keep_audit(10, CHUNK).expect("kept"), 1);
    let kept = body(&node, id);
    let carried = kept.audited.as_ref().expect("carried");
    assert_eq!(carried.message, b"the Message");
    let row = node.read_kept_audit_stream(id, stream).expect("read");
    assert_eq!(row.expect("its audit_stream row").digest, digest.finish());
    let mut read = Vec::new();
    std::io::Read::read_to_end(
        &mut ChunkReader::audited(&node, id, stream)
            .expect("read")
            .expect("it carries one"),
        &mut read,
    )
    .expect("verified");
    assert!(read == content, "the bytes as written");
    drop(node);
    let _ = std::fs::remove_dir_all(&place);
}

/// The latency of a write measured idle — one write after another, nothing
/// else running — in process and over TLS to a Storage node process, and of
/// writes from sixteen threads at once, which share their syncs. Reported
/// on the test's output (`--nocapture`); held to nothing but finishing.
#[test]
fn the_latency_of_a_write_is_measured_and_reported() {
    let test = directory("latency");
    authority(&test);
    let body = vec![b'x'; 1024];
    let local = test_node(&test.join("local"));
    let (median, slowest) = percentiles(&timed(&local, 500, &body));
    eprintln!("LATENCY embedded, in process: median {median:?}, 99th percentile {slowest:?}");

    let local = Arc::new(local);
    let started = std::time::Instant::now();
    let threads: Vec<_> = (0..16u64)
        .map(|thread| {
            let (node, body) = (Arc::clone(&local), body.clone());
            std::thread::spawn(move || {
                for number in 0..100u64 {
                    let record = xmip_persist::storage::JourneyRecord {
                        journey: journey(100_000 + thread * 1000 + number),
                        body: body.clone(),
                        facts: xmip_persist::storage::JourneyFacts::default(),
                    };
                    node.write_journey(&record).expect("written");
                }
            })
        })
        .collect();
    for thread in threads {
        thread.join().expect("a writer");
    }
    let each = started.elapsed() / 1600;
    eprintln!("LATENCY embedded, 16 writers at once: 1600 writes, {each:?} a write");

    let (mut child, says) = spawn("serve", &test.join("remote"));
    let address = heard(&says, "serving ", Duration::from_secs(60));
    let client =
        StorageClient::new(&[address], &issue(&test), TIMEOUT, PASS_OVER).expect("a client");
    let (median, slowest) = percentiles(&timed(&client, 500, &body));
    eprintln!("LATENCY embedded, over TLS: median {median:?}, 99th percentile {slowest:?}");
    drop(child.stdin.take());
    let _ = child.wait();
    let _ = std::fs::remove_dir_all(&test);
}
