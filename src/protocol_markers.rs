use crate::protocol_contracts::{ContentProtocol, FrameProtocol, TransportProtocol, XmipProtocol};

#[derive(Debug, Clone, Copy, Default)]
pub struct TcpProtocol;

#[derive(Debug, Clone, Copy, Default)]
pub struct UdpProtocol;

#[derive(Debug, Clone, Copy, Default)]
pub struct MllpProtocol;

#[derive(Debug, Clone, Copy, Default)]
pub struct Hl7V2Protocol;

#[derive(Debug, Clone, Copy, Default)]
pub struct HttpProtocol;

#[derive(Debug, Clone, Copy, Default)]
pub struct FhirProtocol;

#[derive(Debug, Clone, Copy, Default)]
pub struct CanBusProtocol;

#[derive(Debug, Clone, Copy, Default)]
pub struct Nmea2000Protocol;

impl XmipProtocol for TcpProtocol {
    fn id(&self) -> &'static str { "tcp" }
    fn name(&self) -> &'static str { "TCP" }
}
impl TransportProtocol for TcpProtocol {}

impl XmipProtocol for UdpProtocol {
    fn id(&self) -> &'static str { "udp" }
    fn name(&self) -> &'static str { "UDP" }
}
impl TransportProtocol for UdpProtocol {}

impl XmipProtocol for MllpProtocol {
    fn id(&self) -> &'static str { "mllp" }
    fn name(&self) -> &'static str { "MLLP" }
}
impl FrameProtocol<TcpProtocol> for MllpProtocol {}

impl XmipProtocol for Hl7V2Protocol {
    fn id(&self) -> &'static str { "hl7v2" }
    fn name(&self) -> &'static str { "HL7 v2" }
}
impl ContentProtocol<MllpProtocol> for Hl7V2Protocol {}

impl XmipProtocol for HttpProtocol {
    fn id(&self) -> &'static str { "http" }
    fn name(&self) -> &'static str { "HTTP" }
}
impl ContentProtocol<TcpProtocol> for HttpProtocol {}

impl XmipProtocol for FhirProtocol {
    fn id(&self) -> &'static str { "fhir" }
    fn name(&self) -> &'static str { "FHIR" }
}
impl ContentProtocol<HttpProtocol> for FhirProtocol {}

impl XmipProtocol for CanBusProtocol {
    fn id(&self) -> &'static str { "canbus" }
    fn name(&self) -> &'static str { "CAN bus" }
}
impl TransportProtocol for CanBusProtocol {}

impl XmipProtocol for Nmea2000Protocol {
    fn id(&self) -> &'static str { "nmea2000" }
    fn name(&self) -> &'static str { "NMEA 2000" }
}
impl ContentProtocol<CanBusProtocol> for Nmea2000Protocol {}
