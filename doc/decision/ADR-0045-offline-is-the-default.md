# ADR-0045: Offline is the default

- Status: Accepted
- Date: 2026-09-10
- Related: ADR-0015 (packaging), ADR-0021 (current platforms only), ADR-0023
  (the licensing model), ADR-0028 (the Playground, offline by design),
  ADR-0034 (certificate provisioning versus usage),
  doc/architecture/deployment-model.md (air-gapped nodes)

## In brief

- Theme: Operating Xmip
- Subject: What Xmip may assume about the internet, and how a test says it
- Name: Offline is the default
- Order: 12
- Concepts: Offline; online, the switch; packaging online; installing offline

**Installation, operation and the runtime work with no internet at all.
Packaging may happen online — a package is built where the world is
reachable — and what it produces installs and runs where it is not. Every
cluster and every node carries one switch, `online`, false unless the operator
says otherwise, and a test that needs the internet reads that switch and stays
silent without it: the estate's tests work offline, and only the ones that
need the internet run online.**

## Context

The deployment model has said since 2026-08 that an Xmip node may be an
air-gapped appliance, ADR-0023 built the licensing model for sovereign and
regulated sites, ADR-0028 made the Playground offline by design and ADR-0034
drew the line between certificates provisioned online and used offline. What
no record said was the rule those four are instances of, and what a test does
about it. The owner, 2026-09-10: *tests need switches per cluster and node.
One switch being `online = true|false`, for when internet is available or not.
Tests have to work offline, online in cases internet is needed. Installation,
operation and runtime must work offline. Installation can be packaged in an
online state.*

## Decision

### 1. Nothing at runtime reaches for the internet

A node that installs, starts, receives, processes, sends, retains and archives
does so with no route to the internet. A transport that talks to a cloud
service talks to the endpoint it is configured with, which may be on the other
side of the world or on the same rack; the transport does not know and does not
need to. Nothing resolves a public name, fetches a certificate, checks a
license or downloads a module at runtime. ADR-0034's provisioning — Let's
Encrypt, an ACME challenge — is the one online act, and it is provisioning,
done before a node runs or beside it, never by the node's own path.

### 2. Packaging is online, installation is offline

A package — the DSC configuration, the Ansible role, an installer, a module
archive — may be built where the world is reachable: fetching the toolchain,
the crates, the .NET workloads, the native libraries per platform. What it
produces carries everything an installation needs. An installation reads the
package and the local disk and nothing else. Where a package format cannot
carry a dependency, the package is wrong, not the site.

### 3. The switch

Every cluster and every node carries `online`, a boolean, false unless set.
It lives in the node configuration (`[service] online = false`), in the deploy
lists that write it, and in the operator surfaces that read it, so an
operator can see at a glance which nodes are allowed to assume a route out.
`online = true` does not make a node reach out; it records that it may, and
lets the features that need it — a provisioning step, a test — run.

### 4. Tests work offline, and say when they need more

The estate's tests run with no internet, all of them, on a laptop in a tunnel:
loopback sockets, temporary directories, in-process far ends (ADR-0028
clause 5). A test that genuinely needs the internet — the day one does — reads
the switch and does not run without it, saying so rather than failing: in Rust
through the playground's `switch::online()`, which reads `XMIP_ONLINE`, and in
PowerShell through the same variable. The playground's node processes carry
`--online` and publish it, so a cluster's board shows which emulated nodes think
they may reach out; at every stress level the default is that none may.

## Consequences

- `xmip-core-configure` gains `online` on the service section, defaulting to
  false, and the desktop editor round-trips it.
- The DSC and Ansible node configurations write `online = false`; an operator
  sets it true on purpose, per node.
- The playground gains `switch.rs`, the node binary `--online`, the roll
  passes it, and every emulated node's health record says `offline` or
  `online`. There is no test today that needs the internet; the gate exists so
  the first one does not bring the suite online with it.
- Problem 14, the node configuration format, is still open; this record adds
  one field to whichever shape wins and notes that the deploy files write a
  `[node]` table while the runtime reads `[service]` — a drift found on
  2026-09-10 and left for problem 14 to settle.

## Provenance

The rule is the owner's, 2026-09-10, stated in one message; the drafting is the
assistant's on the instruction to proceed. The earlier records it gathers under
one rule are named above.

## Amendment, 2026-09-20: an online node is where the estate fetches from

The owner: *an online node can be used to download Xmip and related software
as Visual Studio Code and extensions.*

Clause 2 says packaging is online and installation is offline, and clause 3
gives every node a switch that records whether it may assume a route out.
Neither said **who does the fetching**, and the unspoken answer had been "a
developer's laptop, somewhere else". That leaves an air-gapped estate with no
account of how software reaches it at all.

- **A node with the online capability is the estate's door.** It fetches what
  the estate needs from the world — Xmip's own releases, the prerequisites of
  `prerequisite.toml`, Visual Studio Code and the Xmip extension, a module a
  provider published — and the offline nodes take it from there rather than
  from the internet. Online capability is ADR-0056's first kind, and this is
  the first thing it is *for* rather than merely a fact about a node.
- **It changes nothing about the message path.** Clause 1 stands whole: no
  node reaches for the internet to receive, process, send, retain or archive.
  Fetching software is provisioning, which clause 2 already places outside the
  path, and it happens whether or not any Journey is running.
- **Offline stays the default, and the fetch is deliberate.** A node does not
  acquire software because it can. Someone asks it to, as someone asks for an
  ACME certificate (ADR-0034) — the one online act the estate already had.
- **What follows, and is not built.** `Install-XmipPrerequisite` installs
  through the machine's own package manager, which assumes the machine can
  reach a feed; on an offline node it cannot, and the cmdlet has no way to be
  handed what an online node already fetched. Where a fetched thing is put,
  how an offline node is pointed at it, and how its integrity is proven are
  all open. They are named here so the gap is on the record.

Agreed 2026-09-20, not yet built.
