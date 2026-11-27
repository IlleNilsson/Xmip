//! A Bluetooth Send Location's far end: a transport listening on the second
//! of two virtual controllers its crate makes over the kernel's `/dev/vhci`
//! (`xmip_transport_bluetooth::controller::Paired`), and the node's Send
//! Location connecting from the first through the kernel's L2CAP sockets,
//! as it reaches any controller. Linux's: no other build links the
//! transport, and the test says so; on Linux, where this machine stands no
//! controllers — `/dev/vhci` not the user's, or `bluetoothd` not on the
//! system bus — it says why.

use super::Standing;

/// The far end on the second controller, and the Send Port reaching it from
/// the first; none where this build links no Bluetooth or this machine
/// stands no controllers.
#[cfg(feature = "transport-bluetooth")]
pub(super) fn paired() -> Option<Standing> {
    cfg_select! {
        target_os = "linux" => {
            use xmip_transport_bluetooth::controller::{Controllers, Paired};
            use xmip_transport_bluetooth::declaration::PSM;
            if let Some(why) = Controllers::unavailable() {
                println!("bluetooth: SKIPPED: {why}");
                return None;
            }
            let far = Paired::stood(PSM, 3, super::BOUND).expect("two controllers");
            let controller = format!("\"{}\"", far.near());
            let settings = [("channel", "3"), ("controller", controller.as_str())];
            Some(Standing::new("bluetooth", Box::new(far), "bt://{far}", &settings, false))
        }
        _ => {
            println!(
                "bluetooth: SKIPPED: a controller is reached through the kernel's L2CAP \
                 sockets, which Linux alone has, so no other build links bluetooth"
            );
            None
        }
    }
}

/// None: this build links no Bluetooth.
#[cfg(not(feature = "transport-bluetooth"))]
pub(super) const fn paired() -> Option<Standing> {
    None
}
