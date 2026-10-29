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

## Amendment, 2026-10-03: one `xmip.toml`, every designer a view of it

The owner, 2026-10-03: *Developers, Operators deal with the one xmip.toml
file … VS Code's Xmip Extension shall work against this one / cluster toml
file*; *At runtime, when they have been published/sectioned there are
multiple.* Developers and operators author one `xmip.toml` per cluster, its
Xmip Applications among its sections; publishing sections it into the files
each node runs (ADR-0031, amendment of this date). The extension opens that
one file, and every designer — Cluster, Node, Receive Port, Receive
Location, Send Port, Send Location, Send Port Group, Prepare, Promote,
Demote, Route, Transformation, Xmip Process — is a view of its own sections of it.

Built 2026-10-03. An Xmip Application is a section of the cluster's file,
`[[xmip_applications]]`, and nowhere else: its `name` and its lists
(`xmip-core-configure`, `XmipApplication` in `application.rs`, `section.rs`,
read by `parse_application`, its one reading). The separate Application
document — its `[application]` header, a binding's `document` path and the
`*.application.toml` files — is deleted: a binding binds the section of
its name and refuses any other key; `binding_problems` refuses one the
configuration does not hold and reports its design's problems, the slice
gives a node only the sections its bindings name, and the runtime reads
each bound section as the node starts. The Playground's RoundTrip
Application is a section of its cluster's `configuration/xmip.toml`, and
each node's configuration is sliced from it. The designer's views are
configure's `views.rs` — one view per kind in the order above, each entry
wherever the file holds it (shared, a node's own, a binding's, an
Application section's) with its values and its path, a Route entry an
Application section with its routes — and its edits `view_edit.rs`, made
in place and refused where they would leave a node or an Application that
read unable to. Section 10 of `xmip_operate.h` became
`xmip_cluster_views_v1`, `xmip_filter_structure_v1`, `xmip_filter_text_v1`
and `xmip_cluster_edit_v1`; `xmip-lsp` answers `xmip/views` and
`xmip/edit` over the one file, and the extension's custom editor is the
Xmip cluster designer, the Application designer's routes and filter rows
its Route view. The Receive Port view lists each Application's
`[[xmip_applications.receive_ports]]` (ADR-0031, amendment 2026-10-01,
read by configure's `port.rs`). Prepare, Promote, Demote and
Transformation are shown and say the configuration does not define them
yet: no key was invented for them.

## Amendment, 2026-10-05: the Operation Desktop is a view of the same file

The owner, 2026-10-05: *Change it, we edit the cluster TOML file, drilling
down to nodes and artifacts from the overview of the cluster.* The
Operation Desktop's Configure page is a view of the cluster's `xmip.toml`
as the VS Code designer is, through the same `xmip_operate.h` section 10,
bound once in .NET as `RuntimeRules.Design`. Section 10 has a fifth
export, `xmip_cluster_slices_v1`, the one slicing (`configure::slice`) for
a surface; `xmip_cluster_views_v1` answers whether the text is a cluster's
or a node's (`document`). The Operation Web has no editor (the owner: *I do
not see that need for Operation Web version*). ADR-0031, amendment
2026-10-05.

## Amendment, 2026-10-13: create, edit, delete; suggestions, lookups, validations

The owner, 2026-10-13, trying the extension: *Nice attempt, but not really
usefull VS Code extension*; what it must do: *Create, Edit, Delete.
Suggestions, Lookups, Validations*; and *Refine it and I'll try again.*
The text editor over the cluster's `xmip.toml` is where a developer works,
so it gains all six, each by clause 5: the rules in Rust, reached through
the runtime's library, and the extension only wiring.

Built 2026-10-13. `xmip-core-configure` says what an editor needs, in the
answer of `xmip_cluster_views_v1`: `written`, where each table, key and
value is (`written.rs`); `references`, each name standing for an entry
declared elsewhere — a Receive Location's `receive_port`, a Send Port
Group's `send_ports`, a Subscription's `destination`, a binding's `name`,
each bound Location's `name` and `node`, a node's own `node_name` — with
what it names and every name it may take (`references.rs`); and `keys`,
every key each table may hold, its kind, words and requirement, read from
configure's own types by listening to their `Deserialize`, so no key is
listed twice (`keys.rs`, `shape.rs`, `probe.rs`). The runtime adds its
`[tuning]` declaration beside them. `xmip_cluster_edit_v1` gains `rename`
(an entry or a node, and every name standing for it), `refer` and
`rename-key`, and `remove-entry` is refused while anything names the entry,
saying which reference holds it, unless `references`, which removes those
too (`reference_edit.rs`). `xmip-lsp` answers completion, hover,
definition, references, the outline, prepare-rename and rename, code
actions — add, rename, delete, delete with its references, and a quick fix
for each problem the runtime reports where the fix is determinable — and
three commands that make the edits; the extension registers **Xmip: Add**,
**Rename** and **Delete**, which ask only what the server sends them to ask.
Parties are not in the configuration yet, so none is suggested.

## Amendment, 2026-10-22: every kind the configuration defines has its view, and the gaps are filled

The owner, 2026-10-22, about the VS Code extension: *Go ahead and fill the
gaps.* The configuration had grown since 2026-10-13, and the editor and the
designer had not followed everywhere. Built 2026-10-22, each by clause 5,
in `xmip-core-configure` below both surfaces:

- **Every kind is defined.** The views are Cluster, Node, Party, Module,
  Receive Port, Receive Location, Send Port, Send Location, Send Port Group,
  Prepare, Promote, Demote, Route, Transformation and Work Process
  (`kinds.rs`). Prepare, Promote, Demote and Transformation list the calls to
  compiled units the file holds, and Module its `[[modules]]` (ADR-0066,
  amendment of this date); no kind is "not defined yet", so a view's
  `defined` is deleted with every use. The Cluster view holds `[operate]`
  and `[provision]` beside the other shared tables.
- **Parties.** `accept.party` names a Party of `[[parties]]`: suggested,
  looked up, renamed with it and guarding its deletion, as every other
  reference (`references.rs`). A new Party's `id` is minted by configure as
  it is added, never typed.
- **What may be set, offered.** Each entry of the views carries `offered`:
  every key its table may hold and does not write, its kind, whether it is
  required, and the words or names it may take — the reference's choices, a
  choice's words, the role words, and in `[tuning]` the runtime's
  declaration, which the runtime hands in with the role words
  (`offered.rs`, `Views::offering`). An array of unnamed tables, a Party's
  `identities`, is offered as the keys of one element — `mechanism`,
  `purpose` with its words `receive` and `send`, `value` — and added by the
  new edit `add-element`. The VS Code designer and the Operation Desktop's
  Configure page both draw it, as keys and values to pick, and hold no rule.
- **The kinds read right.** A key's kind was read wrong where an outer
  table refused its probe before reaching it — `[storage] listen`,
  `certificate`, `key` and `anchors` were offered as `any` — and is read
  now with every table above it given only the way down to it
  (`shape.rs`).
- **The calls.** A call's `module` and `unit` are references, the units
  offered those of the list's capability; an attachment offers only the
  calls whose unit serves the stage it is attached at; and a call's
  `settings` table is completed and explained from its unit's declaration,
  which the views answer as `units` beside the views.

**The technologies' declarations.** Asked what the runtime library the
surfaces load should carry, the owner, 2026-10-22: every technology's
declaration — names, settings, kinds and words, not the technologies'
code — so every Location's settings are suggested and checked on every
surface, each declaration placed once in its technology; and, from two
ways, a `declaration` feature in each technology crate, its code behind the
default, gathered by one crate the surfaces' build links. Decided, not
built (open problem 48): until then a surface's library carries none, and the
file Send Location's `name` pattern, like every transport's settings, is
checked only by a node that loads the transport.

**The runtime's library stays named.** Asked whether the extension should
find the runtime's library itself through the one rule, `RuntimeLibrary`,
the owner kept `xmip.runtime.library` required (2026-10-22): a Rust server
cannot call the .NET rule, and a second writing of it is the copy ADR-0052
deleted on 2026-09-24. The setting's description and the server's sentence
say plainly where to point it, and `doc/getting-started.md` sets it.

## Amendment, 2026-10-22: the Work Process designer

Clause 1's third designer. The owner, 2026-10-22: *I would like
a Work Process to be designed in VS Code, but at the end of the day it is a
compiled piece executed when called upon*; the design format, BPMN 2.0
by default, and what it compiles to are ADR-0066's amendment of this date.

Built 2026-10-22. A `.bpmn` file opens in the **Xmip Work Process
designer**, the extension's default editor for it: Xmip's own TypeScript
and SVG, never bpmn-js (JavaScript, and its license demands a visible
watermark). The design is a standard BPMN 2.0 document with its BPMN DI, so
clause 4 holds as it does for the cluster's file: the text is the design,
the designer a view of it, and an edit is made in place in the XML, the
rest byte for byte. Clause 5 holds with one difference: what a design means,
how it is drawn and edited and what it compiles to are the design format's
(`xmip-core-process-bpmn`) and `xmip-core-process`'s, answered by
`xmip-lsp` itself (`xmip/process`, `xmip/processEdit`,
`xmip/processCompile`), because a design format is a technology and the
runtime's library, a platform service, names none (`architecture.toml`).
**Compile** writes the Work Process unit's crate and its `[[modules]]`
entry beside the design. Which design formats the runtime's library the
.NET surfaces load carries, so that the PowerShell module and the Operation
Desktop could compile a design too, is the owner's to decide, as which
technologies it carries is (amendment 2026-09-28); until then a design is
compiled in VS Code.

The same day, beside the kinds of the amendment above: a **Correlation
Set** is a kind of its own, the cluster's `[[correlations]]`, listed
after Work Process (`configure::kinds`), and a Receive Location's, Receive
Port's, Work Process's or Send Port's `correlation` is a reference to
one, followed, found and renamed as the others are
(`configure::references`; ADR-0031, amendment of this date).

## Amendment, 2026-10-28: a Location is entered by its address alone

The owner, 2026-10-28, of a draft that derived everything an address
already says — the transport, TLS, host, port, path and user — for file,
FTP, FTPS, SFTP, HTTP and HTTPS: *So lets do it.* The draft's questions,
answered with it as proposed: the separate keys go, with no alias, and a
Location given only an address starts.

- **The scheme chooses the transport.** Each transport declares the
  schemes it answers, in one place, `transport::Configured::SCHEMES` —
  `file`, `ftp` and `ftps`, `sftp`, `http` and `https`, `tcp`, `kafka` and
  every other technology's own — and a Location's address, read once by
  `net::scheme_of` (`ConfiguredLocation::scheme`), chooses the one that
  declares its scheme. An address with no scheme, a path such as
  `/var/xmip/in` or `C:\xmip\in`, is a file's (RFC 8089), as `file://` is.
  A node that carries no transport for a Location's scheme refuses to
  start it, naming the schemes it carries; two linked transports declaring
  one scheme are refused the same way (`Linked::scheme_problems`). The
  runtime's catalogue answers each transport's `schemes`, so every surface
  completes and checks a Location's settings by its address: the VS Code
  extension reads them by the scheme of the Location's `address`.
- **The address says the rest.** `Configured::own_terms` hands a technology
  its address after `scheme://`, or whole where the technology reads the
  scheme itself: `ftps://` and `https://` ask for TLS, the user part of
  `sftp://party-x@host/in` or `ftp://party-x@host/in` is who logs in, the
  path of an FTP address the directory listed and stored in, an absent port
  the scheme's own (21, 80, 443). A send names its target in those terms
  (`Sending::target`).
- **Deleted, with every use:** a Location's `transport` key; FTP's `tls`
  setting, `ftps://` saying it; the `user` setting of FTP and SFTP, the
  address saying it; and FTP's `delete_after_retrieve` — the verdict
  decides what becomes of a file read, never a setting (ADR-0024,
  amendment of this date).
- **A Location starts unless it says `start = false`.** `start` defaults to
  `true` on every Receive Location, Send Port and Send Location; what every
  surface shows for one that says `false` is `configure::NOT_STARTED`, now
  *not started: the configuration says false*, where it said *does not say
  true* while only `true` started one (the owner, 2026-10-13).

An HTTP Receive Location entered as `https://` would listen in TLS, which
the HTTP transport does not terminate yet: it is refused as it binds, in
words saying to enter it as `http://`. `xmip-service` links FTP and FTPS
beside file, HTTP and SFTP (the root crate's `transport-ftp`), and the
personal-computer site names FTP and HTTP. Provenance: the ruling is the
owner's, 2026-10-28; the names `SCHEMES`, `own_terms`, `scheme_of`,
`PATH_SCHEME` and `Sending::target`, and the wording of `NOT_STARTED`, are
the assistant's, for the owner to overrule.
