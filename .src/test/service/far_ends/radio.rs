//! The far ends on an IEEE 802.15.4 radio of the kernel's, Linux's alone:
//! the node's Send Location on one interface, [`NEAR`], and its far end on
//! the other, [`FAR`], both on one PAN — the pair Linux's
//! `mac802154_hwsim` makes. Each far end is the end its technology's own
//! crate stands, over the same radio a node opens
//! (`xmip_transport::ieee802154`): a Thread node taking the datagram sent
//! to its port, a Zigbee node taking a transmission and acknowledging it,
//! a `WirelessHART` device answering every request until it holds the
//! Stream. Every socket bound to an interface hears every frame sent to it,
//! so the three are stood one at a time (`aired.rs`), never in `every`
//! (open problem 234); where this machine has no such pair, each says
//! SKIPPED and why.
#![cfg(any(
    feature = "transport-thread",
    feature = "transport-wireless-hart",
    feature = "transport-zigbee"
))]

use xmip_net::ieee802154::{Address, Interface};
use xmip_transport::held::Held;

use crate::far_ends::{BOUND, Standing};

/// The interface the node's Send Location opens.
pub(crate) const NEAR: &str = "wpan0";

/// The interface each far end stands on.
pub(crate) const FAR: &str = "wpan1";

/// A far end stood when its turn comes: `None` where this machine has no
/// pair.
type Stood = fn() -> Option<Standing>;

/// Each far end this build links on a radio, by its Send Port's name.
pub(crate) fn every() -> Vec<(&'static str, Stood)> {
    vec![
        #[cfg(feature = "transport-thread")]
        ("thread", thread as Stood),
        #[cfg(feature = "transport-wireless-hart")]
        ("wireless-hart", wireless_hart as Stood),
        #[cfg(feature = "transport-zigbee")]
        ("zigbee", zigbee as Stood),
    ]
}

/// Where the node's interface is on the air, and the far end's interface,
/// opened; `None`, said, where either is not on this machine.
fn pair(name: &str) -> Option<(Address, Interface)> {
    match (Interface::open(NEAR), Interface::open(FAR)) {
        (Ok(near), Ok(far)) => {
            assert_eq!(
                near.address().pan,
                far.address().pan,
                "{NEAR} and {FAR} on one PAN"
            );
            Some((near.address(), far))
        }
        (near, far) => {
            let why = near.err().or(far.err()).map(|why| why.message);
            println!("{name}: SKIPPED: {}", why.unwrap_or_default());
            None
        }
    }
}

/// A Thread node at the far interface's short address, taking the one
/// datagram the node's Send Location sends to its mesh-local address.
#[cfg(feature = "transport-thread")]
fn thread() -> Option<Standing> {
    use std::sync::Arc;
    use xmip_transport::{Configured as _, Transport as _, arrived::next_arrival};
    use xmip_transport_thread::{Datagram, ThreadTransport};
    let (near, far) = pair("thread")?;
    let at = far.address().short;
    let node = ThreadTransport::new(Arc::new(far), at).timing_out_after(BOUND);
    let to = format!("[{}]:5683", Datagram::address_of(at));
    let far = Box::new(Held::new(to, move || {
        next_arrival(node.receive()?, "no datagram came")?.taken()
    }));
    let address = format!("thread://{NEAR}/{{far}}");
    let rloc16 = near.short.to_string();
    Some(Standing::new(
        "thread",
        far,
        &address,
        &[("rloc16", &rloc16)],
        false,
    ))
}

/// A `WirelessHART` device at the far interface's short address on its
/// PAN, answering every request the node's gateway sends it until it holds
/// a whole Stream.
#[cfg(feature = "transport-wireless-hart")]
fn wireless_hart() -> Option<Standing> {
    use xmip_transport::{Taken, error::protocol_error, ieee802154::Radio};
    use xmip_transport_wireless_hart::OnTheAir;
    let (_, far) = pair("wireless-hart")?;
    let at = far.address();
    let device = OnTheAir::at(at.short);
    let origin = format!("whart://{FAR}/{:04x}", at.short);
    let held = Box::new(Held::new(FAR, move || {
        loop {
            let heard = Radio::receive(&far, BOUND)?
                .ok_or_else(|| protocol_error("the gateway stopped"))?;
            if let Some(answer) = device.answer(at.short, &heard.payload)? {
                Radio::transmit(&far, heard.source, &answer)?;
            }
            let bytes = device.device().held();
            if !bytes.is_empty() {
                return Ok(Taken::new(origin, bytes));
            }
        }
    }));
    let (network, nickname) = (at.pan.to_string(), at.short.to_string());
    Some(Standing::new(
        "wireless-hart",
        held,
        &format!("whart://{NEAR}"),
        &[("network", &network), ("nickname", &nickname)],
        false,
    ))
}

/// A Zigbee node at the far interface's short address, taking the one
/// transmission the node's Send Location sends to its first endpoint and
/// acknowledging it as it is taken.
#[cfg(feature = "transport-zigbee")]
fn zigbee() -> Option<Standing> {
    use std::sync::Arc;
    use xmip_transport::{Configured as _, Transport as _, arrived::next_arrival};
    use xmip_transport_zigbee::ZigbeeTransport;
    let (near, far) = pair("zigbee")?;
    let at = far.address().short;
    let node = ZigbeeTransport::new(Arc::new(far), at).timing_out_after(BOUND);
    let far = Box::new(Held::new(format!("{at:#06x}/1"), move || {
        next_arrival(node.receive()?, "no transmission came")?.taken()
    }));
    let address = format!("zigbee://{NEAR}/{{far}}");
    let short_address = near.short.to_string();
    Some(Standing::new(
        "zigbee",
        far,
        &address,
        &[("short_address", &short_address)],
        false,
    ))
}
