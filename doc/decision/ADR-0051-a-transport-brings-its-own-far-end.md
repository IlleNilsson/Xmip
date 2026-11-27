# ADR-0051: A transport brings its own far end

- Status: Accepted
- Date: 2026-09-11
- Amended: 2026-09-24 — the far ends are the capability's
- Amended: 2026-09-25 — the trait knows the order and the release
- Amended: 2026-11-27 — LoRaWAN's far end is a gateway over UDP, and a
  node its network server
- Related: ADR-0028 (the System Tests: clause 5, the far end is Xmip; the
  amendment of 2026-09-09, every transport declares its ceiling), ADR-0044
  (a technology shares through its capability), ADR-0010 (one protocol,
  both directions)

## In brief

- Theme: Operating Xmip
- Subject: Where the dance that makes a transport its own counterparty is
  written, and who drives it
- Name: A transport brings its own far end
- Order: 9
- Concepts: Loopback; far end; near end; the one adapter

**A transport that can be both ends of one exchange on this machine says so
in its own crate, by implementing the capability's `Loopback` trait: stand
up the far end, say where it listens, send from a fresh near end, take the
one arrival, and declare the ceiling and the refusals that are facts about
the protocol. The System Tests drive every transport through one adapter over
that trait and write no dance of their own. A new transport is a `loopback()`
constructor in its crate and one line in the System Tests' list.**

## Context

ADR-0028 clause 5 made Xmip its own far end: wherever a transport ships both
a server's worth of protocol and a client, the System Tests use them as the
counterparty and stands up nothing external. What that takes is one dance
per protocol — bind, learn the address, send on one thread while the far end
accepts on another, poke a listener whose sender failed so the round is
judged rather than waited on. By 2026-09-11 that dance was written in the
System Tests forty-two times, once per transport, in thirteen files, around
the very session and client each technology already ships for its own tests;
the technology's tests did the same dance a forty-third time. Thirty-six more
transports landed on 2026-09-11 with no adapter at all, and the System Tests
went on exercising forty-two of eighty-four.

The ceiling and the refusals sat in the adapters too — one datagram's 65 507
bytes in the System Tests' `roundtrip.rs`, the SNMP and DHCP ceilings in its
`management.rs` — although the amendment of 2026-09-09 says a ceiling is a
fact about the protocol, written where it comes from.

The owner asked on 2026-09-11 to consolidate, refactor and re-engineer where
needed. This is the re-engineering.

## Decision

### 1. `Loopback` is the capability's

`xmip-core-transport` gains `loopback.rs`: the `Loopback` trait and the
`FarEnd` it stands up. A technology implements `Loopback` on its transport
type and hands out a configured instance from a `loopback()` constructor —
an ephemeral local port, the capability's `LOOPBACK_TIMEOUT` — the way it
already hands out `new`. The trait has a provided `round`: the two-thread
dance with the poke, written once. A protocol whose two ends do not need two
threads — a directory, an in-process bus — overrides `round` and goes in
order.

Shared code goes up, never sideways (ADR-0044): the dance is code every
transport needs, so it lives in the crate every transport depends on.

### 2. The ceiling and the refusals move with it

`Loopback::ceiling` and `Loopback::refuses` are answered by the technology.
The number for a datagram is in the udp crate; the number for an SNMP
message is in the snmp crate. The System Tests read them; they no longer hold
them.

### 3. The System Tests have one adapter

`Looped<L: Loopback>` implements the System Tests' `RoundTrip` over any
loopback, and `all_transports` lists loopbacks. The `RoundTrip` trait stays:
it is the scenarios' view, and a transport the System Tests cannot yet drive
both ends of is still answered one-sided through it. The per-transport
adapter files go as each transport moves; `listen_exchange` goes with the
last of them.

### 4. The technology's tests drive the same round

A technology's own round-trip test calls `loopback().round(payload)` rather
than writing the dance a third time. What the test asserts beyond the round
— the origin URI, the peer, a protocol's acknowledgment — stays the test's.

### 5. Applied in waves

file, tcp, udp and http move with this record. The remaining thirty-eight
adapters move, and the thirty-six transports of 2026-09-11 gain their
loopbacks, in waves of agents each inside its crates, the way the
technologies were built; the System Tests' list grows to eighty-four as they
land. A transport with only one side keeps answering one-sided until it has
both.

## Consequences

- The System Tests' adapter code — some two and a half thousand lines across
  thirteen files — leaves it, and the System Tests' Cargo manifest still names
  every transport, because a loopback is a dependency.
- A technology's crate is the one place its protocol dance, ceiling and
  refusals are written; its tests and the System Tests read the same one.
- Wiring a new transport into the System Tests is a constructor and a line, so
  an assistant building a technology wires it in the same change.
- ADR-0028 clause 5 and its ceiling amendment are amended to point here.

## Alternatives considered

**Keep the adapters in the System Tests and write thirty-six more.** Rejected:
it is the duplication ADR-0044 exists to stop, at the estate's largest
multiplier.

**Grow the `Transport` trait until it can round-trip.** Rejected: `Transport`
is one protocol both directions for the runtime (ADR-0010) and mirrors the C
ABI's vtable; a listen-and-accept far end is a test concern and does not
belong on the runtime's contract.

**A `loopback` feature flag per crate.** Not needed: a loopback is a few
dozen lines over what the crate already ships for its tests, and a runtime
that never calls it pays nothing.

## Provenance

The re-engineering was asked for by the owner on 2026-09-11 — *let's go bold
and consolidate, refactor and re-engineer if needed* — after the System Tests
rolled over forty-two of eighty-four transports. The trait, its home and the
waves are the assistant's drafting.

## Amendment, 2026-09-24: the far ends are the capability's

Problem 25 found the rig written again in every technology: fifty-one
transports over a parent that shared only the traits, each declaring the
struct its far end is — a listener or a socket with its address, a device
held in process, a session map with its counter — and the refusal of a
payload over the ceiling written twenty-nine times, the System Tests' among
them. Shared code goes up
(clause 1), so the rig moved into the capability, and the trait is
unchanged:

- `listening::Listening` over `Accepting`, taken by value, for every TCP far
  end; `bound::Bound` over `Reading` for every datagram far end; `held::Held`,
  an address and one take, for every far end in this process. A technology
  implements `Accepting` or `Reading` on its transport type, or hands a
  closure over the session it serves.
- `standing::Standing`: the sessions an in-process pair has stood up and not
  yet taken, by address, forgotten when the far end is taken.
- `loopback::both_ends` and `loopback::poke`: the two-thread dance and the
  bounded poke, which `Loopback::round` is and a far end that delivers
  onward — SNS to its subscription, Event Grid to its webhook — uses again.
- `ceiling::within`: the one sentence for a payload over a protocol's
  ceiling; `arrived::next_arrival` and `arrived::one_arrival` for the
  arrival a far end hands back.

What a far end does with the exchange once it has it stays the technology's
(clause 2): its protocol.

## Amendment, 2026-09-25: the trait knows the order and the release

The amendment of 2026-09-24 left the trait unchanged, and two things were
still written once per technology. Sixteen technologies — Bluetooth, CAN
bus, CANopen, EtherCAT, Ethernet, file, HART, IO-Link, LoRaWAN, M-Bus,
PROFINET, SQLite, Thread, WirelessHART, wireless M-Bus and Zigbee —
overrode `round` only to call `round_in_order`, and twenty-six overrode
`unblock` with nothing: those sixteen and serial, whose ends exchange in
order and are never released, and the nine datagram technologies — UDP,
`BACnet`, CoAP, DDS, DHCP, KNX, mDNS, SNMP and SSDP — whose far end reads
with its own timeout. Each override was the same fact stated again. The trait
learns both:

- `Loopback::exchanges_in_order`, declared by the technology and `false`
  unless it says otherwise. Where it is `true`, the provided `round` is
  `round_in_order`, and the provided `unblock` releases nothing. The sixteen
  `round` overrides are that declaration now; serial declares it too and keeps
  its `round`, which frames both ends for the payload first.
- `FarEnd::datagram`, answered by the far end, `false` unless it says
  otherwise. `bound::Bound`, the one datagram far end, says `true`, and the
  provided `round` leaves a datagram far end to its own timeout rather than
  poke a TCP port at its address that is not its own. The datagram
  technologies state nothing: the far end they already stand up knows.
- The provided `unblock` is the bounded poke of a TCP listener, as before.
  A technology overrides it only where its far end is released some other
  way — a path to connect to, a frame that ends a transfer — which is what
  the seven overrides left (AWS SQS, ISO-TP, J1939, named pipe, OBD-II, UDS,
  Unix socket) do.

No technology's round changes: what went on one thread still does, and no
far end is poked that was not poked before.

### Provenance

The owner ruled on 2026-09-24, *teach the trait*: the flag and the default
that knows a datagram, an in-process or a TCP address, so the overrides go.
The shape — the flag on `Loopback`, the datagram fact on the far end that
already holds the socket — is the assistant's drafting.

## Amendment, 2026-11-27: LoRaWAN's far end is a gateway over UDP, and a node its network server

**Provenance.** The owner, 2026-11-27, on the transports whose far end is
hardware: *let's do your best for now. I'm not going to buy all that
hardware.* LoRaWAN's far end was a radio and a network server held in the
node's own process (the loopback radio), so no node reached anything
outside itself and the service did not link it (ADR-0015, amendment
2026-11-25). Every choice below is the assistant's, for the owner to strike
or keep.

The boundary a LoRa gateway already has is software: the gateway forwards
what its concentrator hears to one network server over UDP, and sends what
the server gives it. So a node is that server, and a gateway that is no
radio at all stands in for one.

1. **The protocol is Semtech's UDP packet forwarder protocol, version 2**:
   `PROTOCOL.TXT` in Lora-net/packet_forwarder, revision 1.4 — version 2
   since revision 1.3 added `TX_ACK` — and `PROTOCOL.md` in
   Lora-net/sx1302_hal, revision 1.6, which the SX1302 and SX1303
   concentrators take, the same version (both read 2026-11-27). The six
   datagrams — `PUSH_DATA`, `PUSH_ACK`, `PULL_DATA`, `PULL_ACK`,
   `PULL_RESP`, `TX_ACK` — and the `rxpk`, `txpk` and `txpk_ack` JSON they
   carry are written once in the crate, both ends (`datagram.rs`,
   `packet.rs`). A datagram of another version is refused, naming it. LoRa
   Basics Station, Semtech's newer forwarder, speaks its own protocol over
   WebSocket and is not built. The protocol authenticates and encrypts
   nothing between gateway and node — The Things Industries says as much of
   it — so a frame is its device's by its MIC alone, and the network the
   gateways reach a node over is the site's to keep.
2. **A node is the network server; its Location's address is where it
   listens** for the gateways pointed at it, `lorawan://0.0.0.0:1700`, and
   an address with no port listens on 1700 (`declaration::PORT`): the port
   The Things Stack lists for the packet forwarder and ChirpStack's gateway
   bridge listens on, so a gateway set up for either is pointed at a node by
   its server's address alone. Semtech ships 1680 and sx1302_hal 1730; a
   gateway's own file names whichever.
3. **The Locations of a node at one address share one socket**, and a
   Receive and a Send Location of one device share its session — its
   counters and its fragments — through `transport::sharing`, as a serial
   port is shared (ADR-0064, amendment 2026-11-15): one gateway sends every
   device it hears to one address. One Location reads the socket at a time
   and keeps what it read for the others, woken by `xcore::wake`
   (`gateways.rs`). A gateway asking for downlinks from a new address, a
   packet forwarder started again, is sent again what it had not answered.
4. **A Receive Location takes what one device sends up**, its socket bound
   as the node starts, the same frame a second gateway heard taken once. A
   confirmed frame up is answered in the device's first receive window —
   one second after it ended on its gateway's clock, `RECEIVE_DELAY1` of
   the Regional Parameters — before the receive cycle ends, since the
   window does not wait for it: acceptance of an uplink is at-most-once.
5. **A Send Location sends at once**, through the gateway that heard the
   device last, on its `frequency` at its `data_rate`, by default EU868's
   second receive window, 869.525 MHz at SF12BW125, at 14 dBm: where a
   Class C device listens between its uplinks. A confirmed Send Location
   confirms a Stream's last frame and waits for the device's acknowledgement
   in its next frame up. A Send Location alone binds the socket as it first
   sends, as every Send Location's is bound, and waits for the gateway's
   next `PULL_DATA`, within its `keepalive_interval`, 10 s as Semtech ships
   it. A Class A device, which listens just after its own uplink, is not
   reached yet (open problem 219).
6. **A session is activated by personalization**: the device's address is
   the `dev_addr` setting, and its keys are the secret its Location names, a
   `password` secret of 64 hexadecimal digits, the network session key's
   and then the application session key's, as network servers show them;
   no secret kind is added (ADR-0015, amendment 2026-11-25). It is read as
   each Stream is sent and as each receive opens its first frame. Joining
   over the air is not built.
7. **A frame a real device sends is opened whole**: a frame with no
   payload carries no port, frame options are skipped under the MIC that
   covers them, and a payload on port 0 is under the network session key;
   until 2026-11-27 each was refused. No MAC command is answered.
8. **The far end is a device behind a gateway**: the crate's own packet
   forwarder (`forwarder.rs`), a `Radio` that forwards each frame in a
   `PUSH_DATA`, asks for downlinks each keepalive and answers each
   `PULL_RESP` at once, whatever moment its `tmst` names, and the device
   the crate already had, now putting fragments down back together through
   the network server's own reassembly (`device.rs`, `fragment.rs`).
   `LorawanTransport::loopback()` stands both on this machine over UDP, so
   LoRaWAN no longer exchanges in order (the amendment of 2026-09-25 listed
   it), and a round goes on two threads. The loopback radio is deleted: no
   test needs a server in the device's process any more.

## Amendment, 2026-11-27: Thread, Zigbee and WirelessHART ride one IEEE 802.15.4 radio, an interface of Linux's kernel

**Provenance.** The owner, 2026-11-27, on the transports whose far end is
hardware: *let's do your best for now. I'm not going to buy all that
hardware.* Thread, Zigbee and WirelessHART each had a radio held in its
own process alone, so no node reached anything outside itself and the
service did not link them (ADR-0015, amendment 2026-11-25). The owner gave
the Linux test computer two virtual radios the same day, `wpan0` and
`wpan1`, which the kernel's `mac802154_hwsim` makes, on one PAN, brought up
at boot. Where the boundary lives, its shape and every choice below are the
assistant's, for the owner to strike or keep.

1. **The boundary is the kernel's MAC, through a datagram socket.** Linux
   hands a user process an 802.15.4 interface as an `AF_IEEE802154`
   socket. A raw one writes the MAC header itself and asks for
   `CAP_NET_RAW`; a datagram one asks for no capability, and neither is
   made in a network namespace but the first (the kernel's
   `ieee802154_create`, net/ieee802154/socket.c, read 2026-11-27); a node
   holds no capability. So a radio is a datagram socket bound to the
   interface's own PAN and short address, which the interface is asked for
   (`SIOCGIFADDR`, which mac802154's `mac802154_wpan_ioctl` answers,
   net/mac802154/iface.c, read the same day); a send
   hands the kernel one frame's payload for a short address on that PAN,
   and the kernel writes the header — a data frame, the PAN once, the two
   short addresses, its own sequence — and the check sequence; a receive
   reads the payload and the short address that sent it. One frame carries
   116 bytes above the MAC: 127 less a 9-byte header and the 2-byte check
   sequence.
2. **Placed once, in the two layers that own it.** No 802.15.4 crate or
   module existed: architecture.toml, the transport capability and the
   libraries name none. A technology crate of its own, as ethernet is for
   EtherCAT and PROFINET and can-bus for CAN, would be a new repository,
   which is the owner's to make. The socket is the operating system's, as
   the TCP connect and the named pipe are, so it is the network library's
   (`net::ieee802154`: `Interface`, `Address`, `Heard`, `MAX_PAYLOAD`),
   which all three already depend on, its calls in that crate's one folder
   of unsafe code (ADR-0050, amendment 2026-11-27). The seam each radio
   implements is the transport capability's, `ieee802154::Radio`, beside
   the serial `line::Line`, where each technology depends and its error is
   the transports' own: a frame's payload to a short address, the next
   heard and who sent it, and how a receive meets a quiet air — an
   interface waits for the next frame, a node in process looks and returns
   at once. The interface implements it there; `ieee802154::interface`
   opens one by name, and `ieee802154::agreeing` holds a setting to it.
   Thread and Zigbee each declared that trait for themselves, identically,
   and WirelessHART one of its own.
3. **No technology writes a MAC header.** Thread's MAC frame, its PAN fixed
   at `0xFACE` and its CRC-16/KERMIT, is deleted; `lowpan.rs` keeps the
   6LoWPAN headers, each frame sent to the next hop's short address, and
   the crate no longer depends on codec. Zigbee's network frame began above
   the MAC already, its `MAX_NPDU` now the radio's `MAX_PAYLOAD`, each frame
   sent to the short address its network header names: one hop, no route.
   IEC 62591's DLPDU header is the MAC header — the network identifier the
   PAN, the nicknames short addresses — and WirelessHART wrote a MAC header
   of its own and then the same fields again; its DLPDU on a radio is now
   the specifier, the packet and the MIC, 111 bytes of packet where 103
   were.
4. **A Location's address names the radio.** `thread://wpan0`,
   `zigbee://wpan0` and `whart://wpan0` are the interface; `loopback` is
   each technology's node in process, kept because every test, the System
   Tests' adapter and every box without an 802.15.4 radio drive it, as
   can-bus's loopback bus is kept. A Thread or Zigbee address may name
   after the radio where a send goes, as its targets do,
   `thread://wpan0/[fd00::ff:fe00:2]:5683` and `zigbee://wpan0/0x0002/1`.
   No setting is added: Thread's `rloc16` and Zigbee's `short_address` must
   be the interface's short address and WirelessHART's `network` its PAN,
   since the kernel's MAC sends from the interface's own, and another is
   refused, naming both; WirelessHART's gateway is the interface's short
   address where it is `0xF981` in process.
5. **Linux's alone.** Elsewhere `Interface::open` refuses in words; so it
   does where the kernel makes no 802.15.4 socket, naming why: Ubuntu's
   `/etc/modprobe.d/blacklist-rare-network.conf` keeps `ieee802154_socket`
   from loading on demand (`alias net-pf-36 off`), so a machine loads it
   (`modprobe ieee802154_socket`), and the kernel makes none in a network
   namespace but the first, so no namespace of a test's own makes an
   interface, as one does a CAN interface and a veth pair.
6. **Each far end is its crate's own, on the other interface.** The node's
   Send Location opens `wpan0`; the far end stands on `wpan1`
   (`.src/test/service/far_ends/radio.rs`): a Thread node taking the
   datagram sent to its port, a Zigbee node taking the transmission and
   acknowledging it, and a WirelessHART device answering every request
   until it holds the Stream — `loopback::OnTheAir`, the device the
   loopback radio holds, which answers one frame at a time whatever radio
   carried it. The kernel hands every frame sent to an interface to every
   socket bound to it, so the three are carried one at a time, a node each
   (`aired.rs`), never at once with the rest (open problem 234).
