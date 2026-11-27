//! Every transport this build links whose far end is on an IEEE 802.15.4
//! radio — Thread, Zigbee, `WirelessHART` — carries a file through the node
//! to it, as `linked.rs` carries the rest (the owner, 2026-11-27: *let's do
//! your best for now. I'm not going to buy all that hardware*). The node's
//! Send Location opens one interface of the kernel's and its far end
//! stands on the other, the pair Linux's `mac802154_hwsim` makes
//! (`far_ends/radio.rs`). An interface is one only in the first network
//! namespace, so no namespace of the test's own makes one, and every socket
//! bound to an interface hears every frame sent to it: each technology is
//! carried by a node of its own, one after the other. Linux's alone; where
//! the machine has no such pair, each says SKIPPED and why, and runs
//! nothing; where it does, a far end that does not take the file whole
//! fails the test.

/// The far ends on the machine's radios, kept beside every other far end.
#[cfg(target_os = "linux")]
#[path = "far_ends/radio.rs"]
mod radio;

#[test]
fn a_file_dropped_in_is_sent_over_every_radio_to_its_far_end() {
    cfg_select! {
        all(
            target_os = "linux",
            any(
                feature = "transport-thread",
                feature = "transport-wireless-hart",
                feature = "transport-zigbee"
            )
        ) => {
            for (name, standing) in radio::every() {
                if let Some(one) = standing() {
                    super::linked::carried(&format!("service-radio-{name}"), |_| vec![one]);
                }
            }
        }
        target_os = "linux" => {
            println!("radios: this build links no transport on an 802.15.4 radio");
        }
        _ => {
            println!(
                "radios: SKIPPED: an IEEE 802.15.4 interface is Linux's, and xmip-service \
                 links thread, wireless-hart and zigbee there alone"
            );
        }
    }
}
