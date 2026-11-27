//! A `LoRaWAN` Send Location's far end: a device behind a gateway pointed at
//! the node, the node its network server. The gateway is the technology's
//! own packet forwarder, speaking Semtech's UDP protocol to the node, and
//! the device the technology's own, with the frame, the keys and the
//! fragments the node's side is written with
//! (`xmip_transport_lorawan::BehindGateway`). The node listens where its
//! Send Location's address says, a port this far end asks the operating
//! system for and gives back; the session's keys are drawn for it and set on
//! the node as the secret its Send Port names (`linked.rs`).

use std::sync::Arc;
use std::time::Duration;

use xmip_transport_lorawan::{BehindGateway, Device, EndDevice, Forwarder, Keys};

use super::{BOUND, Standing};

/// The device's address, as its Location's `dev_addr` writes it.
const DEVICE: u32 = 0x2601_1b2c;

/// The gateway: Semtech's example identifier, `AA555A0000000000`, but its
/// last byte.
const GATEWAY: [u8; 8] = [0xaa, 0x55, 0x5a, 0, 0, 0, 0, 1];

/// How often the gateway asks the node for downlinks: a tenth of a second,
/// where a packet forwarder asks every ten, so the node's Send Location,
/// which binds its socket as it first sends, is asked at once.
const KEEPALIVE: Duration = Duration::from_millis(100);

/// The device behind its gateway, and the Send Port reaching it.
pub(super) fn device() -> Standing {
    let drawn = xmip_codec::random::array::<32>();
    let keys = Keys::from_hex(&xmip_codec::hex::encode(&drawn)).expect("32 bytes are keys");
    let node = vacant();
    let gateway = Forwarder::pointed_at(&node, GATEWAY, BOUND)
        .expect("a gateway's socket")
        .keeping_alive(KEEPALIVE);
    let device = Arc::new(Device::new(DEVICE, keys));
    let device = EndDevice::new(Arc::new(gateway), device).waiting(BOUND);
    let far = Box::new(BehindGateway::new(node, device));
    let dev_addr = DEVICE.to_string();
    Standing::new(
        "lorawan",
        far,
        "lorawan://{far}",
        &[("dev_addr", &dev_addr)],
        false,
    )
    .secured(&keys.to_hex())
}

/// A port of loopback nothing holds, for the node to listen on: the
/// operating system's pick for a socket bound and let go.
fn vacant() -> String {
    let socket = std::net::UdpSocket::bind("127.0.0.1:0").expect("a port");
    socket.local_addr().expect("its address").to_string()
}
