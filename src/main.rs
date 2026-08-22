use xmip_core::disposition::{admit, Action, Arrival, Identity};

/// Seven Streams arriving at Xmip, one for each way a Stream can end.
///
/// The point of the run is the final column: what Xmip kept. Nothing before
/// transport authorization, the Stream after it, the Message once Validation
/// fails, and ownership only once a Journey exists.
fn main() {
    println!("Xmip ingress and message disposition");
    println!("Stream -> identity -> authentication -> authorization -> Message -> Journey");

    let arrivals = [
        // No identity at all. Xmip never learns who this is.
        Arrival {
            receive_location: "drop/anonymous",
            transport: "file",
            origin_uri: "file:///drop/anonymous/a-1.dat",
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
            origin_uri: "https://partner-y.example/xmip/post",
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
            origin_uri: "https://partner-z.example/xmip/post",
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
        // Through the gate, but the bytes are not what they claim to be.
        // The sender is known, so the Stream is kept.
        Arrival {
            receive_location: "drop/partner-x",
            transport: "file",
            origin_uri: "file:///drop/partner-x/d-4.edi",
            bytes: 4182,
            action: Action::Poll,
            identity: Identity::Implied("party:partner-x"),
            authentication: Ok("path, permissions and source verified"),
            authorization: Ok("poll allowed"),
            message_creation: Err("not deserializable as edi-x12 at byte 2044"),
            contract: "edi-x12",
            validation: Err("not attempted"),
            subscriptions: &[],
            can_respond: false,
        },
        // A Message exists, and the Contract rejects it. Answered immediately.
        Arrival {
            receive_location: "https/partner-x",
            transport: "http",
            origin_uri: "https://partner-x.example/xmip/post",
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
            origin_uri: "file:///drop/partner-x/f-6.json",
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
        // The whole way through.
        Arrival {
            receive_location: "drop/partner-x",
            transport: "file",
            origin_uri: "file:///drop/partner-x/g-7.json",
            bytes: 4182,
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

    let mut kept: Vec<(&str, &str)> = Vec::new();

    for arrival in arrivals.iter() {
        let (disposition, _journey) = admit(arrival);
        kept.push((arrival.origin_uri, disposition.kept()));
    }

    println!();
    println!("What Xmip kept");
    for (uri, what) in kept.iter() {
        println!("  {:<18} {}", uri, what);
    }
}
