//! The far ends of the Send Locations that announce or answer in one
//! datagram: an mDNS Send Location announces a service, an SSDP one a
//! device, a DHCP one answers a client with a lease. Each crate's own
//! loopback carries a Stream its own way — asking the sender back for it in
//! chunks, or as a client's informs to a server — which a node's Send
//! Location does not do (open problem 170), so each far end here is what
//! hears the one datagram a node sends, read by its technology's own
//! reading: a browser, a control point, a client. What a node is sent for
//! each is what its protocol carries whole.

#[cfg(any(
    feature = "transport-dhcp",
    feature = "transport-mdns",
    feature = "transport-ssdp"
))]
use xmip_transport::{FarEnd, bound::Bound};

#[cfg(any(feature = "transport-mdns", feature = "transport-ssdp"))]
use xmip_transport::Configured;

#[cfg(any(
    feature = "transport-dhcp",
    feature = "transport-mdns",
    feature = "transport-ssdp"
))]
use super::BOUND;

/// What an mDNS Send Location announces: its service's TXT strings, one
/// `key=value` line each, as a browser reads them back.
#[cfg(feature = "transport-mdns")]
pub(crate) const SERVICE: &str = "txtvers=1\npath=/probe\n";

/// What an SSDP Send Location sends: a whole notification, which it sends
/// as it is and a control point takes whole.
#[cfg(feature = "transport-ssdp")]
pub(crate) const DEVICE: &str = "NOTIFY * HTTP/1.1\r\n\
                                 HOST: 239.255.255.250:1900\r\n\
                                 CACHE-CONTROL: max-age=1800\r\n\
                                 LOCATION: http://probe.example/description.xml\r\n\
                                 NT: urn:xmip:device:Probe:1\r\n\
                                 NTS: ssdp:alive\r\n\
                                 USN: uuid:xmip-probe::urn:xmip:device:Probe:1\r\n\r\n";

/// What a DHCP Send Location answers with: an offer's options, one
/// `name=value` line each, the type its address names first, as a client
/// reads them back.
#[cfg(feature = "transport-dhcp")]
pub(crate) const LEASE: &str = "message-type=offer\nlease-time=3600\nsubnet-mask=255.255.255.0\n";

/// A browser at a port of its own, taking the one service a node announces
/// to it.
#[cfg(feature = "transport-mdns")]
pub(crate) fn browser() -> Box<dyn FarEnd> {
    let browser = xmip_transport_mdns::MdnsTransport::new("127.0.0.1:0").timing_out_after(BOUND);
    let bound = browser.bind_udp().expect("a browser's socket");
    Box::new(Bound::new(
        move |socket: &std::net::UdpSocket| {
            let services = browser.receive_datagram(socket)?;
            xmip_transport::arrived::next_arrival(services, "an announcement naming no service")?
                .taken()
        },
        bound,
    ))
}

/// A control point at a port of its own, taking the one notification a
/// node sends it.
#[cfg(feature = "transport-ssdp")]
pub(crate) fn control_point() -> Box<dyn FarEnd> {
    let point = xmip_transport_ssdp::SsdpTransport::new("127.0.0.1:0").timing_out_after(BOUND);
    let bound = point.bind_udp().expect("a control point's socket");
    Box::new(Bound::new(
        move |socket: &std::net::UdpSocket| point.receive_datagram(socket)?.taken(),
        bound,
    ))
}

/// A client at a port of its own, taking the one reply a node answers it
/// with: its options, as the technology writes a message's options.
#[cfg(feature = "transport-dhcp")]
pub(crate) fn client() -> Box<dyn FarEnd> {
    use xmip_transport::error::{classify, protocol_error};
    use xmip_transport_dhcp::message::{self, BOOTREPLY, MAX_MESSAGE};

    let bound =
        xmip_transport::socket::bind_udp("127.0.0.1:0", Some(BOUND)).expect("a client's socket");
    Box::new(Bound::new(
        |socket: &std::net::UdpSocket| {
            let mut buffer = vec![0u8; MAX_MESSAGE * 2];
            let (read, peer) = socket
                .recv_from(&mut buffer)
                .map_err(|e| classify("awaiting the reply", &e))?;
            let reply = message::decode(&buffer[..read])?;
            if reply.op != BOOTREPLY {
                return Err(protocol_error("a client is answered with a reply"));
            }
            let origin = format!("dhcp://{peer}?xid={:#010x}", reply.xid);
            Ok(xmip_transport::Taken::new(origin, reply.option_lines()))
        },
        bound,
    ))
}
