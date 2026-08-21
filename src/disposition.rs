//! Executable demonstration of ingress and message disposition.
//!
//! Records the runtime lifecycle from Xmip-Architecture-Specification-v1.2 section 2
//! and the disposition rules from ADR-0013 as running code. Every gate is printed,
//! and every refusal states what Xmip kept.

use crate::journey_model::{create_initial_message_with_treatment, Journey, Message};
use crate::vertical_slice::business_treatment;

/// Where an identity came from, if anywhere.
pub enum Identity {
    /// Nothing presented by the caller, nothing implied by the Receive Location.
    Absent,
    /// Implied by the Receive Location itself, such as a partner drop folder.
    Implied(&'static str),
    /// Presented by the caller on the transport.
    Presented(&'static str),
}

/// What the caller is attempting against Xmip.
pub enum Action {
    Send,
    Post,
    Poll,
}

impl Action {
    fn name(&self) -> &'static str {
        match self {
            Action::Send => "send",
            Action::Post => "post",
            Action::Poll => "poll",
        }
    }
}

/// One incoming Stream and the outcome of every gate it meets.
pub struct Arrival {
    pub receive_location: &'static str,
    pub transport: &'static str,
    pub stream_uri: &'static str,
    pub bytes: usize,
    pub action: Action,
    pub identity: Identity,
    pub authentication: Result<&'static str, &'static str>,
    pub authorization: Result<&'static str, &'static str>,
    pub message_creation: Result<&'static str, &'static str>,
    pub contract: &'static str,
    pub validation: Result<&'static str, &'static str>,
    pub subscriptions: &'static [&'static str],
    pub can_respond: bool,
}

/// What Xmip did with the Stream, and what it kept.
pub enum Disposition {
    RefusedAtIdentification,
    RefusedAtAuthentication,
    RefusedAtAuthorization,
    RefusedAtMessageCreation,
    StoredAtValidation,
    DeadMessageQueue,
    Routed,
}

impl Disposition {
    /// What Xmip retained. This is the column that matters.
    pub fn kept(&self) -> &'static str {
        match self {
            Disposition::RefusedAtIdentification => "nothing",
            Disposition::RefusedAtAuthentication => "nothing",
            Disposition::RefusedAtAuthorization => "nothing",
            Disposition::RefusedAtMessageCreation => "Stream, by xmip-core-retain",
            Disposition::StoredAtValidation => "Message, by xmip-core-retain",
            Disposition::DeadMessageQueue => "Message, in the Xmip DMQ",
            Disposition::Routed => "Message, owned by Xmip",
        }
    }
}

fn step(n: &str, name: &str, detail: &str) {
    println!("  {:>2}  {:<26} {}", n, name, detail);
}

fn refused(gate: &str, kept: &str) {
    println!("      refused at {}", gate);
    println!("      kept: {}   audited as a transport event", kept);
}

/// Walk one Arrival through the lifecycle, printing each step.
///
/// Returns the Disposition and, where one was created, the Journey.
pub fn admit(a: &Arrival) -> (Disposition, Option<Journey>) {
    println!();
    println!(
        "{}   {}   {} bytes   {}",
        a.receive_location,
        a.stream_uri,
        a.bytes,
        a.action.name()
    );

    // Steps 1 to 3: transport security. Always, and before any content is read.
    match a.identity {
        Identity::Absent => {
            step("1", "transport identity", "none presented, none implied");
            refused("transport identification", "nothing");
            return (Disposition::RefusedAtIdentification, None);
        }
        Identity::Implied(who) => {
            step("1", "transport identity", who);
            println!("      implied by the Receive Location, no credential presented");
        }
        Identity::Presented(who) => {
            step("1", "transport identity", who);
        }
    }

    match a.authentication {
        Ok(how) => step("2", "transport authentication", how),
        Err(why) => {
            step("2", "transport authentication", why);
            refused("transport authentication", "nothing");
            return (Disposition::RefusedAtAuthentication, None);
        }
    }

    match a.authorization {
        Ok(how) => step("3", "transport authorization", how),
        Err(why) => {
            step("3", "transport authorization", why);
            refused("transport authorization", "nothing");
            return (Disposition::RefusedAtAuthorization, None);
        }
    }

    // Step 4: Message creation. Nothing before this point parsed any content.
    match a.message_creation {
        Ok(what) => step("4", "message creation", what),
        Err(why) => {
            step("4", "message creation", why);
            println!("      refused at message creation, no Message exists");
            println!("      kept: Stream, by xmip-core-retain   the sender is known");
            return (Disposition::RefusedAtMessageCreation, None);
        }
    }

    step("5", "default promotion", "message.type, destination");
    step(
        "6",
        "configuration inspect",
        "message security not required here",
    );
    step("7", "message identity", "skipped");
    step("8", "message authentication", "skipped");
    step("9", "message authorization", "skipped");
    step("10", "contract implication", a.contract);
    step("11", "deserialization", "ok");

    // Step 12: Validation. A failure here stops before any Journey exists.
    match a.validation {
        Ok(what) => step("12", "validation", what),
        Err(why) => {
            step("12", "validation", why);
            if a.can_respond {
                println!(
                    "      responded to the caller immediately, the transport carries a reply"
                );
            } else {
                println!("      no reply channel, the audit record is the only trace");
            }
            println!("      no Journey created");
            println!("      kept: Message, by xmip-core-retain");
            return (Disposition::StoredAtValidation, None);
        }
    }

    // Step 13: Journey creation. Only now, and only once.
    let (journey, message) =
        create_initial_message_with_treatment(a.stream_uri, business_treatment());
    step("13", "journey created", "one Journey for this interchange");
    println!(
        "      journey {}   message {}   state {:?}",
        journey.journey_id, message.message_id, journey.state
    );

    // Routing. Subscriptions are matched within the Journey, not outside it.
    if a.subscriptions.is_empty() {
        println!("      published, 0 subscriptions matched");
        println!("      to the Xmip DMQ, final disposition, notified");
        return (Disposition::DeadMessageQueue, Some(journey));
    }

    println!(
        "      published, {} subscriptions matched",
        a.subscriptions.len()
    );
    for s in a.subscriptions {
        println!("        {}  executed within this Journey", s);
    }

    (Disposition::Routed, Some(journey))
}
