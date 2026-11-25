//! The far ends on a serial line, each a pseudo-terminal's device end
//! (`xmip_transport_serial::terminal`), its line's end the path a node's
//! Send Location opens as it opens a device: what a serial Send Location
//! writes its frame to, and the device a protocol's master on a serial line
//! writes a Stream to — a HART field device, an IO-Link device, an M-Bus
//! meter — answering each frame as the device its own crate stands in
//! process answers it. Unix's: Windows has no pseudo-terminal, a line there
//! being a COM port with a device on it.

#[cfg(any(
    feature = "transport-hart",
    feature = "transport-io-link",
    feature = "transport-m-bus",
    feature = "transport-serial"
))]
use xmip_transport::FarEnd;

#[cfg(all(
    unix,
    any(
        feature = "transport-hart",
        feature = "transport-io-link",
        feature = "transport-m-bus",
        feature = "transport-serial"
    )
))]
use {super::BOUND, xmip_transport_serial::Framing, xmip_transport_serial::terminal::Terminal};

/// Where this machine has no pseudo-terminal: `name`'s far end is not stood,
/// and the test says so.
#[cfg(all(
    not(unix),
    any(
        feature = "transport-hart",
        feature = "transport-io-link",
        feature = "transport-m-bus",
        feature = "transport-serial"
    )
))]
fn none(name: &str) -> Option<Box<dyn FarEnd>> {
    println!("{name}: not on this machine: a pseudo-terminal is Unix's");
    None
}

/// A fresh pseudo-terminal, its device's end waiting [`BOUND`].
#[cfg(all(
    unix,
    any(
        feature = "transport-hart",
        feature = "transport-io-link",
        feature = "transport-m-bus",
        feature = "transport-serial"
    )
))]
fn terminal() -> Terminal {
    Terminal::pair(BOUND).expect("a pseudo-terminal")
}

/// A device on a fresh pseudo-terminal, answering every frame the line
/// writes, read as `framing` reads it, as `hear` answers it, until `held`
/// holds a whole Stream: what it took, with `scheme`'s origin.
#[cfg(all(
    unix,
    any(
        feature = "transport-hart",
        feature = "transport-io-link",
        feature = "transport-m-bus"
    )
))]
fn answering(
    scheme: &str,
    framing: Framing,
    hear: impl FnMut(&[u8]) -> xmip_transport::Result<Option<Vec<u8>>> + Send + 'static,
    held: impl Fn() -> Option<Vec<u8>> + Send + 'static,
) -> Box<dyn FarEnd> {
    let terminal = terminal();
    let origin = format!("{scheme}://{}", terminal.path());
    terminal.answering(framing, hear, move || {
        held().map(|bytes| xmip_transport::Taken::new(origin.as_str(), bytes))
    })
}

/// The device a serial Send Location writes one frame to, framed by its
/// default delimiter, a carriage return and a line feed.
#[cfg(feature = "transport-serial")]
#[allow(
    clippy::unnecessary_wraps,
    reason = "a machine with no pseudo-terminal stands none"
)]
pub(crate) fn line() -> Option<Box<dyn FarEnd>> {
    cfg_select! {
        unix => Some(terminal().far_end(Framing::Delimited(b"\r\n".to_vec()))),
        _ => none("serial"),
    }
}

/// The field device at polling address 0 a HART Send Location writes a
/// Stream to, as HART's own loopback stands it on the SDK's bus.
#[cfg(feature = "transport-hart")]
#[allow(
    clippy::unnecessary_wraps,
    reason = "a machine with no pseudo-terminal stands none"
)]
pub(crate) fn field_device() -> Option<Box<dyn FarEnd>> {
    cfg_select! {
        unix => {
            use std::sync::Arc;
            use xmip_sdk::serial::Device as _;
            use xmip_transport_hart::{Device, Frame, Identity, loopback::OnTheBus};
            let identity = Identity {
                manufacturer: 0x26,
                device_type: 0xe5,
                device_id: 0x0a_1b2c,
            };
            let device = Arc::new(Device::new(identity));
            let held = Arc::clone(&device);
            let on_the_bus = OnTheBus(device);
            Some(answering(
                "hart",
                Framing::Measured(Frame::measure),
                move |frame| on_the_bus.hear(frame),
                move || Some(held.held()).filter(|bytes| !bytes.is_empty()),
            ))
        }
        _ => none("hart"),
    }
}

/// The device an IO-Link Send Location writes a Stream to as one ISDU, its
/// Stream parameter held empty until then, as IO-Link's own loopback stands
/// it: taken once the write is answered whole.
#[cfg(feature = "transport-io-link")]
#[allow(
    clippy::unnecessary_wraps,
    reason = "a machine with no pseudo-terminal stands none"
)]
pub(crate) fn io_link_device() -> Option<Box<dyn FarEnd>> {
    cfg_select! {
        unix => {
            use std::sync::{Arc, Mutex};
            use xmip_core::lock::Locked;
            use xmip_transport_io_link::{Device, MasterMessage, STREAM_PARAMETER};
            let (index, subindex) = STREAM_PARAMETER;
            let device = Device::new(0).with_parameter(index, subindex, Vec::new());
            let device = Arc::new(Mutex::new(device));
            let held = Arc::clone(&device);
            Some(answering(
                "iolink",
                Framing::Measured(MasterMessage::measure),
                move |frame| {
                    let master = MasterMessage::decode(frame, 0)?;
                    Ok(Some(device.locked().answer(&master).encode()))
                },
                move || {
                    let device = held.locked();
                    let bytes = device.parameter(index, subindex).unwrap_or_default();
                    (device.idle() && !bytes.is_empty()).then(|| bytes.to_vec())
                },
            ))
        }
        _ => none("io-link"),
    }
}

/// The meter at primary address 1 an M-Bus Send Location writes a Stream
/// to, as M-Bus's own loopback stands it on the SDK's bus.
#[cfg(feature = "transport-m-bus")]
#[allow(
    clippy::unnecessary_wraps,
    reason = "a machine with no pseudo-terminal stands none"
)]
pub(crate) fn meter() -> Option<Box<dyn FarEnd>> {
    cfg_select! {
        unix => {
            use std::sync::Arc;
            use xmip_sdk::serial::Device as _;
            use xmip_transport_m_bus::frame::Frame;
            use xmip_transport_m_bus::loopback::OnTheBus;
            use xmip_transport_m_bus::meter::{Identity, Meter};
            let identity = Identity {
                ident: 12_345_678,
                manufacturer: *b"XMP",
                version: 1,
                medium: 7,
            };
            let meter = Arc::new(Meter::new(identity).at_primary(1));
            let held = Arc::clone(&meter);
            let on_the_bus = OnTheBus(meter);
            Some(answering(
                "mbus",
                Framing::Measured(Frame::measure),
                move |frame| on_the_bus.hear(frame),
                move || Some(held.held()).filter(|bytes| !bytes.is_empty()),
            ))
        }
        _ => none("m-bus"),
    }
}
