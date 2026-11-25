//! The far ends on a link of the kernel's, Linux's alone: a CAN interface,
//! which the node reaches through can-bus's `socketcan`, and an Ethernet
//! interface's raw socket, through ethernet's `packet`. Each stands on an
//! interface of its own, which `namespaced.rs` makes in a user and network
//! namespace of the test's own, where no administrator is asked: a virtual
//! CAN interface for each CAN technology, as ISO-TP, UDS and OBD-II answer
//! under the same identifiers, and a veth pair for each Ethernet one, the
//! node's end and the far end's. Each far end is the end its technology's
//! own crate stands in process, on the kernel's link: an ECU collecting a
//! message, a receiver clearing a transfer, a tester polling, a `CANopen`
//! node or an `EtherCAT` ring answering every frame until its object holds
//! the Stream, a PROFINET device taking its cycles (the owner, 2026-11-25:
//! *just do your best for now*).

use std::sync::Arc;
use std::time::Duration;

use xmip_transport::error::protocol_error;
use xmip_transport::{Configured, FarEnd, Taken, Transport, arrived::next_arrival, held::Held};

use super::{BOUND, Standing};

/// The virtual CAN interfaces the test makes, one for each technology.
pub(crate) const CAN: [&str; 6] = [
    "xmip-can",
    "xmip-canopen",
    "xmip-isotp",
    "xmip-j1939",
    "xmip-obd",
    "xmip-uds",
];

/// The veth pairs the test makes, the node's end and the far end's, one for
/// each technology.
pub(crate) const ETHERNET: [(&str, &str); 3] = [
    ("xmip-eth", "xmip-eth-far"),
    ("xmip-ecat", "xmip-ecat-far"),
    ("xmip-pnet", "xmip-pnet-far"),
];

/// What a can-bus Send Location is sent: what one classical frame carries
/// whole, eight bytes.
const FRAME: &str = "CANprobe";

/// The node a `CANopen` Send Location writes to, and the station an
/// `EtherCAT` one does.
const NODE: u8 = 1;
const STATION: u16 = 0x1001;

/// The far ends on the kernel's links, in the order of their names, each on
/// the interface the test made for it.
pub(crate) fn kernel() -> Vec<Standing> {
    let mut all = Vec::new();
    standing! {all, "transport-can-bus", "can-bus", Some(frame("xmip-can")),
    "can://xmip-can", ["id" = 385], false, FRAME}
    standing! {all, "transport-canopen", "canopen", Some(node("xmip-canopen")),
    "canopen://xmip-canopen", ["node" = 1], false}
    standing! {all, "transport-ethercat", "ethercat", Some(ring("xmip-ecat-far")),
    "ethercat://xmip-ecat", ["source" = "02:00:00:00:00:01", "station" = 4097], false}
    standing! {all, "transport-ethernet", "ethernet", Some(wire("xmip-eth-far")),
    "ethernet://xmip-eth",
    ["source" = "02:00:00:00:00:01", "destination" = "02:00:00:00:00:02"], false}
    standing! {all, "transport-iso-tp", "iso-tp", Some(ecu("xmip-isotp")),
    "isotp://xmip-isotp", ["id" = 2016], false}
    standing! {all, "transport-j1939", "j1939", Some(receiver("xmip-j1939")),
    "j1939://xmip-j1939", ["source" = 128, "pgn" = 61184, "destination" = 33], false}
    standing! {all, "transport-obd-ii", "obd-ii", Some(tester("xmip-obd")),
    "obd://xmip-obd", [], false}
    standing! {all, "transport-profinet", "profinet", Some(device("xmip-pnet-far")),
    "profinet://xmip-pnet",
    ["controller" = "02:00:00:00:00:01", "device" = "02:00:00:00:00:02"], false}
    standing! {all, "transport-uds", "uds", Some(server("xmip-uds")),
    "uds://xmip-uds", [], false}
    all
}

/// The CAN interface `interface`, as a node's Location opens it, which the
/// test made.
#[cfg(any(
    feature = "transport-can-bus",
    feature = "transport-canopen",
    feature = "transport-iso-tp",
    feature = "transport-j1939",
    feature = "transport-obd-ii",
    feature = "transport-uds"
))]
fn bus(interface: &str) -> Arc<dyn xmip_transport_can_bus::Bus> {
    xmip_transport_can_bus::open_bus(interface).unwrap_or_else(|why| panic!("{interface}: {why}"))
}

/// The Ethernet interface `interface`, as a node's Location opens it, which
/// the test made.
#[cfg(any(
    feature = "transport-ethercat",
    feature = "transport-ethernet",
    feature = "transport-profinet"
))]
fn link(interface: &str) -> Arc<dyn xmip_transport_ethernet::Link> {
    xmip_transport_ethernet::open_link(interface).unwrap_or_else(|why| panic!("{interface}: {why}"))
}

/// A socket on the interface taking the one frame a can-bus Send Location
/// puts on it.
#[cfg(feature = "transport-can-bus")]
fn frame(interface: &str) -> Box<dyn FarEnd> {
    let bus = bus(interface);
    Box::new(Held::new(interface, move || {
        let frame = bus
            .receive(BOUND)?
            .ok_or_else(|| protocol_error("no frame came"))?;
        Ok(Taken::new(frame.origin(bus.name()), frame.data))
    }))
}

/// `CANopen` node [`NODE`], its Stream object empty, answering every frame
/// the master puts on the interface until the object holds a whole Stream.
#[cfg(feature = "transport-canopen")]
fn node(interface: &str) -> Box<dyn FarEnd> {
    use xmip_transport_can_bus::Bus as _;
    use xmip_transport_canopen::{Node, STREAM_OBJECT};
    let bus = bus(interface);
    let (index, subindex) = STREAM_OBJECT;
    let node = Node::new(NODE).with_object(index, subindex, Vec::new());
    let origin = format!("canopen://{interface}/{NODE}");
    Box::new(Held::new(interface, move || {
        loop {
            let asked = bus
                .receive(BOUND)?
                .ok_or_else(|| protocol_error("the master stopped"))?;
            node.transmit(&asked)?;
            while let Some(answer) = node.receive(Duration::ZERO)? {
                bus.transmit(&answer)?;
            }
            if let Some(bytes) = node.object(index, subindex).filter(|held| !held.is_empty()) {
                return Ok(Taken::new(origin, bytes));
            }
        }
    }))
}

/// An ECU collecting the one message an ISO-TP Send Location segments.
#[cfg(feature = "transport-iso-tp")]
fn ecu(interface: &str) -> Box<dyn FarEnd> {
    use xmip_transport_iso_tp::{ECU_ID, IsoTpTransport};
    let bus = bus(interface);
    let ecu = IsoTpTransport::new(Arc::clone(&bus), bus, ECU_ID).timing_out_after(BOUND);
    Box::new(Held::new(interface, move || ecu.collect()))
}

/// Node 33 clearing the transfer a J1939 Send Location opens to it.
#[cfg(feature = "transport-j1939")]
fn receiver(interface: &str) -> Box<dyn FarEnd> {
    let bus = bus(interface);
    let node = xmip_transport_j1939::J1939Transport::new(Arc::clone(&bus), bus, 33)
        .timing_out_after(BOUND);
    Box::new(Held::new(interface, move || node.collect()?.taken()))
}

/// A tester polling the parameter an OBD-II Send Location answers as the
/// ECU: its request waits in the node's socket for the send.
#[cfg(feature = "transport-obd-ii")]
fn tester(interface: &str) -> Box<dyn FarEnd> {
    use xmip_transport_obd_ii::{FUNCTIONAL, ObdTransport};
    let bus = bus(interface);
    let link = xmip_transport_iso_tp::IsoTpTransport::new(Arc::clone(&bus), bus, FUNCTIONAL)
        .timing_out_after(BOUND);
    let tester = ObdTransport::new(link);
    Box::new(Held::new(interface, move || {
        next_arrival(tester.receive()?, "the ECU answered nothing")?.taken()
    }))
}

/// An ECU serving the data identifier a UDS Send Location writes,
/// answering its write once taken.
#[cfg(feature = "transport-uds")]
fn server(interface: &str) -> Box<dyn FarEnd> {
    use xmip_transport_iso_tp::{ECU_ID, IsoTpTransport};
    let bus = bus(interface);
    let link = IsoTpTransport::new(Arc::clone(&bus), bus, ECU_ID).timing_out_after(BOUND);
    let ecu = xmip_transport_uds::UdsTransport::new(link);
    Box::new(Held::new(interface, move || ecu.serve()?.taken()))
}

/// A raw socket on the far end of the pair taking the one frame an Ethernet
/// Send Location puts on it under Xmip's `EtherType`.
#[cfg(feature = "transport-ethernet")]
fn wire(interface: &str) -> Box<dyn FarEnd> {
    use xmip_transport_ethernet::XMIP_ETHERTYPE;
    let link = link(interface);
    Box::new(Held::new(interface, move || {
        loop {
            let frame = link
                .receive(BOUND)?
                .ok_or_else(|| protocol_error("no frame came"))?;
            if frame.ethertype == XMIP_ETHERTYPE {
                return Ok(Taken::new(frame.origin(link.name()), frame.payload));
            }
        }
    }))
}

/// A ring of one slave at [`STATION`], its Stream object empty, at the far
/// end of the pair: every frame the master puts on it passes the ring and
/// goes back, until the object holds a whole Stream and its last answer is
/// read.
#[cfg(feature = "transport-ethercat")]
fn ring(interface: &str) -> Box<dyn FarEnd> {
    use xmip_transport_ethercat::{STREAM_OBJECT, Segment, Slave};
    use xmip_transport_ethernet::Link as _;
    let link = link(interface);
    let (index, subindex) = STREAM_OBJECT;
    let ring = Segment::new(vec![Slave::new(STATION).with_object(
        index,
        subindex,
        Vec::new(),
    )]);
    let origin = format!("ethercat://{interface}/{STATION:#06x}");
    Box::new(Held::new(interface, move || {
        loop {
            let frame = link
                .receive(BOUND)?
                .ok_or_else(|| protocol_error("the master stopped"))?;
            ring.transmit(&frame)?;
            while let Some(back) = ring.receive(Duration::ZERO)? {
                link.transmit(&back)?;
            }
            let held = ring.with_slave(STATION, |slave| {
                let bytes = slave.object(index, subindex).unwrap_or_default();
                (slave.idle() && !bytes.is_empty()).then(|| bytes.to_vec())
            });
            if let Some(bytes) = held.flatten() {
                return Ok(Taken::new(origin, bytes));
            }
        }
    }))
}

/// A PROFINET device at the far end of the pair taking the run of cycles a
/// controller's Send Location puts on it: a transport there whose own
/// address is the device's, as cycles are taken by who they are sent to.
#[cfg(feature = "transport-profinet")]
fn device(interface: &str) -> Box<dyn FarEnd> {
    use xmip_transport_ethernet::Mac;
    let link = link(interface);
    let device = xmip_transport_profinet::ProfinetTransport::new(
        link,
        Mac([0x02, 0, 0, 0, 0, 2]),
        Mac([0x02, 0, 0, 0, 0, 1]),
    )
    .timing_out_after(BOUND);
    Box::new(Held::new(interface, move || {
        next_arrival(device.receive()?, "no cycle came")?.taken()
    }))
}
