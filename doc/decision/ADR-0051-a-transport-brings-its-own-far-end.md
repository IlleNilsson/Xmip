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
