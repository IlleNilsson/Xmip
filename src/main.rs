use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use xmip_core::disposition::{admit, Action, Arrival, Identity};
use xmip_core::transport::{Arrived, FileTransport, Transport};

/// A directory standing in for a partner drop.
fn drop_directory() -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock before epoch")
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("xmip-drop-{}-{nanos}", std::process::id()));
    fs::create_dir_all(&dir).expect("creating the drop directory");
    dir
}

/// Find one of the Streams the transport actually read.
fn pick<'a>(arrived: &'a [Arrived], name: &str) -> &'a Arrived {
    arrived
        .iter()
        .find(|a| a.origin_uri.contains(name))
        .unwrap_or_else(|| panic!("the transport did not read {name}"))
}

/// Seven Streams arriving at Xmip, one for each way a Stream can end.
///
/// Two of them are real: written to a directory, then read back through
/// FileTransport, so their origin and byte count come from the filesystem
/// rather than from this file. The other five describe refusals that happen
/// before any bytes matter.
///
/// The point of the run is the final column: what Xmip kept. Nothing before
/// transport authorization, the Stream after it, the Message once Validation
/// fails, and ownership only once a Journey exists.
fn main() {
    println!("Xmip ingress and message disposition");
    println!("Stream -> identity -> authentication -> authorization -> Message -> Journey");

    // Put two files where a partner would drop them, then let the transport
    // find them. Nothing below invents an origin or a length.
    let dir = drop_directory();
    let transport = FileTransport::new(&dir);
    transport
        .send(
            "order-1001.edi",
            b"ISA*00*          *00*          *ZZ*PARTNERX",
        )
        .expect("dropping the edi file");
    transport
        .send(
            "bundle-2002.json",
            br#"{"resourceType":"Bundle","type":"message","entry":[]}"#,
        )
        .expect("dropping the fhir bundle");

    let arrived = transport.receive().expect("reading the drop directory");
    println!(
        "\n{} read {} Stream(s) from {}",
        transport.name(),
        arrived.len(),
        dir.display()
    );

    let edi = pick(&arrived, "order-1001.edi");
    let fhir = pick(&arrived, "bundle-2002.json");

    let arrivals = vec![
        // No identity at all. Xmip never learns who this is.
        Arrival {
            receive_location: "drop/anonymous",
            transport: "file",
            origin_uri: "file:///drop/anonymous/a-1.dat".to_string(),
            bytes: 1204,
            action: Action::Send,
            identity: Identity::Absent,
            authentication: Err("not attempted"),
            authorization: Err("not attempted"),
            message_creation: Err("not attempted"),
            contract: "none",
            validation: Err("not attempted"),
            subscriptions: &[],
            can_respond: false,
        },
        // Identity presented, but it does not hold up.
        Arrival {
            receive_location: "https/partner-y",
            transport: "http",
            origin_uri: "https://partner-y.example/xmip/post".to_string(),
            bytes: 3310,
            action: Action::Post,
            identity: Identity::Presented("certificate CN=partner-y"),
            authentication: Err("certificate expired"),
            authorization: Err("not attempted"),
            message_creation: Err("not attempted"),
            contract: "none",
            validation: Err("not attempted"),
            subscriptions: &[],
            can_respond: true,
        },
        // Authenticated, but not permitted to post here.
        Arrival {
            receive_location: "https/partner-z",
            transport: "http",
            origin_uri: "https://partner-z.example/xmip/post".to_string(),
            bytes: 880,
            action: Action::Post,
            identity: Identity::Presented("jwt sub=partner-z"),
            authentication: Ok("signature and issuer verified"),
            authorization: Err("may not post to this Receive Location"),
            message_creation: Err("not attempted"),
            contract: "none",
            validation: Err("not attempted"),
            subscriptions: &[],
            can_respond: true,
        },
        // A real file. Through the gate, but the bytes are not what they claim
        // to be. The sender is known, so the Stream is kept.
        Arrival {
            receive_location: "drop/partner-x",
            transport: "file",
            origin_uri: edi.origin_uri.clone(),
            bytes: edi.bytes.len(),
            action: Action::Poll,
            identity: Identity::Implied("party:partner-x"),
            authentication: Ok("path, permissions and source verified"),
            authorization: Ok("poll allowed"),
            message_creation: Err("not deserializable as edi-x12, envelope ends early"),
            contract: "edi-x12",
            validation: Err("not attempted"),
            subscriptions: &[],
            can_respond: false,
        },
        // A Message exists, and the Contract rejects it. Answered immediately.
        Arrival {
            receive_location: "https/partner-x",
            transport: "http",
            origin_uri: "https://partner-x.example/xmip/post".to_string(),
            bytes: 2210,
            action: Action::Post,
            identity: Identity::Presented("jwt sub=partner-x"),
            authentication: Ok("signature and issuer verified"),
            authorization: Ok("post allowed"),
            message_creation: Ok("msg created from fhir bundle"),
            contract: "fhir -> xmip-core-contract-fhir",
            validation: Err("Patient.identifier missing at /entry[0]/resource"),
            subscriptions: &[],
            can_respond: true,
        },
        // Accepted and valid, but nobody wants it.
        Arrival {
            receive_location: "drop/partner-x",
            transport: "file",
            origin_uri: "file:///drop/partner-x/f-6.json".to_string(),
            bytes: 1990,
            action: Action::Poll,
            identity: Identity::Implied("party:partner-x"),
            authentication: Ok("path, permissions and source verified"),
            authorization: Ok("poll allowed"),
            message_creation: Ok("msg created from fhir bundle"),
            contract: "fhir -> xmip-core-contract-fhir",
            validation: Ok("ok"),
            subscriptions: &[],
            can_respond: false,
        },
        // A real file, the whole way through.
        Arrival {
            receive_location: "drop/partner-x",
            transport: "file",
            origin_uri: fhir.origin_uri.clone(),
            bytes: fhir.bytes.len(),
            action: Action::Poll,
            identity: Identity::Implied("party:partner-x"),
            authentication: Ok("path, permissions and source verified"),
            authorization: Ok("poll allowed"),
            message_creation: Ok("msg created from fhir bundle"),
            contract: "fhir -> xmip-core-contract-fhir",
            validation: Ok("ok"),
            subscriptions: &["process:order-flow", "sendPort:orders-out"],
            can_respond: false,
        },
    ];

    let mut kept: Vec<(String, &str)> = Vec::new();

    for arrival in arrivals.iter() {
        let (disposition, _journey) = admit(arrival);
        kept.push((arrival.origin_uri.clone(), disposition.kept()));
    }

    println!("\nWhat Xmip kept");
    for (n, (uri, what)) in kept.iter().enumerate() {
        println!("  {}  {what:<28} {uri}", n + 1);
    }

    fs::remove_dir_all(&dir).ok();
}
