# ADR-0064: Developers design in VS Code, and an Xmip Application holds what they draw

- Status: Accepted
- Accepted: 2026-09-26, the owner, answering each question below as asked
- Date: 2026-09-26
- Related: ADR-0014 (operator surfaces; its 2026-09-10 amendment made the VS
  Code extension the developer's face), ADR-0031 (configuration is TOML),
  ADR-0046 (a route technology is a source the filter reads), ADR-0052 (the
  surfaces share one model), `doc/planning/market-position.md` (*every
  competitor leads with a visual designer*), `doc/terminology.md`

## In brief

- Theme: Operating Xmip
- Subject: How a developer designs routes, transforms and processes, and where the
  design lives
- Name: Developers design in VS Code
- Order: 20
- Concepts: Xmip Application; designer; binding

**A developer designs graphically in VS Code, as in BizTalk: routes first,
then transforms, then processes. What they draw belongs to an Xmip Application —
the integration, drawn once and deployed to whichever nodes run it — and a
node's configuration binds it: which Application, on which node, with which
addresses. Every design is a text document in the repository; the designer
is a view of that text, its rules are Xmip's own in the Rust language server,
and only the drawing is in the extension.**

## Context

The owner, 2026-09-26: *So let's turn the focus to Developers. In VS Code a
developer needs graphical help to define routes, maps and processes. Like
BizTalk.* The VS Code extension validated a node's TOML and nothing else.
`market-position.md` had already called the missing designer the widest gap
Xmip has.

What each designer would edit, that day: routes are Subscriptions whose
filters the runtime already evaluates, written as text in one node's TOML;
transforms have seventeen transform technologies declared and no transform document;
processes are a name and settings, with no flow definition, and the
Xmip Process vocabulary is phase C's first open item.

## Decision

### 1. Routes first, then transforms, then processes

The owner, from three: routes first — they run already, so a drawn route can
be seen routing a Message in the Playground the same day. Transforms follow; the
process designer comes after the Xmip Process vocabulary is settled.

### 2. An Xmip Application holds the design

The owner, from two (an application definition, or each node's
configuration): **an application definition.** A route is part of an
integration, drawn once and deployed to many nodes; a node's configuration
*binds* an Application — which one, where, with which addresses and
credentials per environment — as BizTalk's bindings do. The same route is
never written again per node.

Built 2026-09-26. The Xmip Application document is `XmipApplicationDocument`
in `xmip-core-configure` (`application.rs`, described in
`module/platform/configure/doc/application.md`): `[application]` with its
name, and `[[receive_locations]]`, `[[xmip_processes]]`, `[[send_ports]]`,
`[[send_port_groups]]` and `[[subscriptions]]` — each Subscription `route`'s
own, a filter in Xmip's expression language (ADR-0066) and its
destination — with no address in it. The binding is `[[applications]]` in the
node's configuration (`binding.rs`, `node-configuration.md`): the
Application's name, the path of its document, and each bound Receive Location
and Send Port with its node, transport, address, start and a reference to its
credentials. `configure::bind` joins the two and refuses an Application the
node was not given and a Location the Application does not declare; the
runtime's execution tree takes the Locations the bindings give its node and
every Subscription of every bound Application, and a bound Subscription routes
a Message at arrival (`arrival.rs`,
`a_bound_applications_subscription_routes_a_message`). `xmip_validate_v1`
reads either document and tells them apart by the `[application]` table, so
every surface validates an Application as it validates a node. Running an
Application in the Playground is the next slice.

### 3. Its name is Xmip Application

The owner, from three (Xmip Application, Integration, Xmip Solution):
**Xmip Application**, BizTalk's word with the prefix Xmip Process carries.
`doc/terminology.md` gains the entry.

### 4. A design is text; the designer is a view of it

Every Xmip Application and everything in it is a TOML document (ADR-0031) in
the repository — diffed, reviewed and merged like code. A designer opens
that text and writes it back; a developer may edit either and the other
follows. Nothing is held only in a designer's state.

### 5. Xmip's rules in Rust, the drawing in the extension

What may connect to what, what a filter means, what is valid, how a design is
laid out: `xmip-lsp`, the Rust language server, answering the extension over
the language server protocol's custom requests, calling the runtime's library
for every rule the runtime owns (ADR-0052, code is placed once). The drawing
is a webview in the extension, the one place TypeScript lives, and it holds
no rule (the owner's rule of 2026-09-24).

Built 2026-09-26, the routes designer's first slice, clauses 4 and 5. The
rules are `xmip-core-configure`'s: an Application's routes as a graph
(`routes.rs`), a filter's text and its structure of rows and And and Or
groups, turned one into the other byte for byte (`filter.rs`), and the edits
a designer makes — declare a Receive Location, an Xmip Process or a Send
Port, add a Subscription, set its filter, connect it to a target — made to
the TOML in place, comments and layout kept (`edit.rs`). The runtime's
library forwards each through `xmip_operate.h` section 10
(`xmip_application_routes_v1`, `xmip_filter_structure_v1`,
`xmip_filter_text_v1`, `xmip_application_edit_v1`). `xmip-lsp` answers four
custom requests from them, places each node on the canvas and returns an
edit as the one text edit that makes it. The extension's custom editor, the
Xmip Application designer, draws the graph in SVG and edits a filter as rows
of property, operator, value and kind; it holds no rule and never writes
TOML, and the text editor and the designer follow each other both ways.

## Consequences

- The configuration model gains the Xmip Application document and the node's
  binding of it; `configure` parses both, the runtime starts what a node
  binds, and the Playground runs Applications instead of hand-written
  Subscriptions.
- The first designer draws an Application's routes: Receive Locations, the
  Subscriptions and their filters (property, operator, value, and/or
  groups, as BizTalk's filter dialog), and where each routes — an
  Xmip Process or a Send Port.
- Transforms need a transform document and a built transform technology before their
  designer; processes need the vocabulary and a flow definition.

## Provenance

**The owner's**, 2026-09-26: the requirement quoted in Context, and clauses
1, 2 and 3, each chosen from the options named there.

**The assistant's**: clauses 4 and 5 — design as text, the rules in the
language server, the drawing in a webview — drawn from the estate's standing
rules (ADR-0031; code is placed once; no TypeScript beyond the extension).
Each is the owner's to strike.

## Amendment, 2026-09-26: the extension aids the whole path

The owner, 2026-09-26: *The Xmip VS Code extension should aid all from
Receive Location, runtime configuration to Send Locations, to aid the
developers.* Routes were the first designer, not the extension's scope. It
aids everything a developer writes along the path:

- **Receive and Send Locations** — choose a transport from those Xmip has,
  fill in its settings in a form, choose the contract, the identity and the
  TLS it presents or requires; every setting explained and validated as it is
  typed.
- **The runtime configuration** — the node's document and its bindings of
  Xmip Applications: which Application, which node takes which Location, the
  addresses and credential references per environment.
- **Routes, transforms and Xmip Processes** — the designers of clauses 1 and 3.

What a form shows is never written in the extension: every technology
declares its own settings — names, kinds, defaults, what is required, what
each means — in its own crate, and the language server reads that one
declaration through the runtime's library (code is placed once). The same
declaration validates the TOML at start, fills the desktop editor, and
documents the technology.

Built 2026-09-26, the declaration. Its shape is `xmip-core`'s `settings`
(`Settings`, `Setting`, `Kind`, `Presence`, `Applies`): each setting's name,
kind — text, integer with its range, boolean, duration, address, a secret's
name, one of a list — default or requirement, one sentence of meaning and
the side that reads it, plain `const` data, and `Settings::read`, the one
reading of a Location's values through it. All 84 transports implement
`transport::Configured` — the declaration as `SETTINGS`, and `configured`,
the one constructor, taking what the declaration read — and all 21 Rust
contracts declare theirs through `ContractFactory::settings`; a technology
with none declares so, and each technology's test holds its declaration
sound and builds from a Location through it. A Location gains `settings`,
`contract` and `contract_settings` (`node-configuration.md`), and
`configure::location_problems` refuses an unknown setting, one for the other
side, a wrong kind and a missing required one, each naming the technology
and the setting, for every Location a node validates or starts. The
runtime's `catalogue` holds the declarations of the technologies it carries
and answers them through `xmip_operate.h` section 12,
`xmip_technology_catalogue_v1`, bound in `Xmip.Abi` as `RuntimeCatalogue`;
`xmip-lsp` completes and explains a Location's transport, contract and
settings from it and answers `xmip/technologies` for the form the next
slice draws. The runtime names no technology (`architecture.toml`: a
platform service depends on no technology repository), so a technology
enters its catalogue through `catalogue::carry`; which technologies the
runtime library the surfaces load carries is the owner's to decide.

## Amendment, 2026-09-28: a node carries what it loads

`catalogue::carry` is called when a node loads a technology
(`xmip-core-runtime`, startup phase 6), so the catalogue answers what a node
in this process loaded, and every validation in the process holds a
Location to it. A node that starts also holds each Location to the
declarations of every transport its program linked, before anything loads.
The runtime library the surfaces load runs no node and carries nothing
(ADR-0018, amendment 2026-09-28; open problem 20); which technologies it
should carry is still the owner's to decide.
