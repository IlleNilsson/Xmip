# Compatibility

What runs where: each feature against each target Xmip is to run on or reach.
A draft of 2026-10-06, to be worked on; no cell is verified yet.

The owner, 2026-10-06: *As an endpoint we must be able to target MCU's.* Rust
compiles to bare metal as C does, so an MCU endpoint is a `no_std` build.
And: *It is Rust aka C, the basics should run on all devices.* So the
foundation is to be `no_std` throughout; today only `xmip-core` is.
The owner, 2026-10-08: an MCU node runs the whole message path like any
other node type, validating what it receives and what it sends, and has no
Operation (ADR-0015, amendment 2026-10-08, quotes him).

| Feature | Windows x64 | Linux x64 | Edge (Linux boards: Raspberry Pi, Arduino UNO Q / Portenta X8) | MCU (Meadow, Pico, Arduino, ESP32, STM32 …) |
|---|---|---|---|---|
| Foundation `xmip-core` | built | written, not run | written, not run | `no_std`, not run |
| Foundation message, journey, stream, event, party, context | built | written, not run | written, not run | needs `no_std` |
| Xmip Service (node) | built | written, not run | as Linux, untested | does not apply: no OS |
| Xmip Host Service | in-process | written, not run | written, not run | does not apply |
| Embedded Storage (RocksDB) | built | written, not run | written, not run | does not apply |
| Ledger, Journeys, retry | built | written, not run | written, not run | does not apply |
| Receive and Send Locations | built | written, not run | written, not run | needs `no_std` |
| Device transports (MQTT, CoAP, Modbus …) | node side | written, not run | written, not run | `no_std` client, not designed |
| Contract validation | built | written, not run | written, not run | needs `no_std` |
| Transform | decided | decided | decided | decided, needs `no_std` |
| Prepare | decided | decided | decided | decided, needs `no_std` |
| Work Process | decided | decided | decided | decided, needs `no_std` |
| Identity and TLS (X.509 and hybrid) | library; not linked in the service | written, not run | written, not run | needs a `no_std` TLS |
| Audit | built | written, not run | written, not run | forwarded to a node |
| Operation surfaces (CLI, PowerShell, GUI) | built | written, not run | written, not run | none: no Operation on a device |
| GPU for routing, transformation and processing | open | open | open | does not apply |
| Service registration | Windows service | systemd | systemd | does not apply |

*Does not apply* is where Xmip stands today, not a limit: a cell loses it once
that piece is designed, coded, built and tested for the target.

*Written, not run*: the code is written for the target, and nothing runs
there until the owner lifts Windows only.
