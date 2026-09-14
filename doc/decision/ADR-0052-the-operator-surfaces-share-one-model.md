# ADR-0052: The operator surfaces share one model

- Status: Accepted
- Date: 2026-09-11
- Related: ADR-0014 (the operator surfaces; amendments 2026-08-26, the ABI
  is the interface into Xmip; 2026-09-05, the web GUI monitors; 2026-09-09,
  the .NET binding is one project in xmip-core-abi; 2026-09-10, the
  configuration tool has two faces), ADR-0027 (the operator boundary),
  ADR-0041 (health is a mood and does not propagate), ADR-0044 (a technology
  shares through its capability)

## In brief

- Theme: Operating Xmip
- Subject: What the `xmip` executable, the two GUIs, the PowerShell module
  and the VS Code extension have in common, and where that lives
- Name: The operator surfaces share one model
- Order: 10
- Concepts: Xmip.Surface; the scope tree; Holding says why; the surface is
  chosen, never guessed; runtime discovery

**Every operator surface reads the same operator boundary and shows the same
tree of scopes, moods and evidence. What they share — the surface over the
ABI, the snapshot surface, the scope tree and its rollup, how the runtime
library is found, how a status is said in English, how a TOML document is
read — is one .NET library, `Xmip.Surface`, beside the binding in
`xmip-core-abi`, and every .NET surface is a thin face over it. A scope that
is Holding says why on the spot: the worst leaf beneath it and that leaf's
evidence, at the banner, at the tile, at the row. The web GUI monitors and
does nothing else. Paused is a mood. The surface a host reads is chosen in
its configuration, never guessed from a file in a temp directory.**

## Context

A survey on 2026-09-11 of the four surfaces the owner named as the priority —
the ABI binding, the `xmip` executable, the MAUI desktop and the VS Code
extension — found the shape ADR-0014 asks for, with the same code written
several times over and the record broken in the places nobody had tested:

- `Beneath(candidate, scope)`, the scope-tree predicate, three times
  character for character across `FileOperator`, `SampleOperator` and
  `Cluster.razor`, and a fourth variant beside them. The surface choice —
  playground snapshot, else native, else sample, then start a node — twice,
  in the web host and the desktop host. TOML configuration reading four
  times. Status to English twice, in `NativeOperator` and the CLI. The mood
  to color map twice, in the stylesheet where ADR-0041 puts it and in an
  inline gradient where it does not.
- Three ways to find the runtime library: the GUIs from configuration, the
  language server from an argument, an environment variable or beside its
  binary, the CLI from a positional argument an operator types.
- The web host loads the runtime and starts a node, and shows Pause and
  Resume to anyone who sets a role — ADR-0014's 2026-09-05 amendment says
  the web GUI reads snapshots and nothing else.
- Both hosts read a playground snapshot in the temp directory *first*, so a
  stale file silently replaces a live node.
- Paused is detected by matching the evidence string `paused by`, and the
  sample surface reports a paused scope as Stressed; `HealthState.Paused`
  is never tested for.
- A Holding scope shows the word and a count. The worst leaf and its
  evidence are computed and used to decide whether to show a *follow the
  error* button, and never rendered beside the word. The owner, watching
  the board the same day: *I still get Holding and I do not know why.*
- The GUIs have no tests; the CLI has none and emits neither the JSON
  ADR-0014 clause 10 asks for nor a follow mode; the extension's TypeScript
  is built and linted by nothing; two repositories run a Rust workflow over
  .NET; the MAUI project carries three platforms it does not target and a
  sample path that does not exist.

The owner's instruction, 2026-09-11: *consolidate, refactor and re-engineer
if needed. The abi, cli, MAUI gui and VS Code extension need work. Those
are the current priority.* And on the button: *there is no need for
"follow the error". An operator or developer will drill down to the error
or find it in the audit, logs.*

## Decision

### 1. `Xmip.Surface` is what every .NET surface shares

A class library, `dotnet/Xmip.Surface` in `xmip-core-abi`, beside
`Xmip.Abi`. ADR-0014's amendment of 2026-09-09 put the binding in the ABI's
repository because the ABI is the interface into Xmip; the model every
surface builds on the binding goes to the same place, by ADR-0044's rule
read for .NET: code that several surfaces need lives where they all already
depend. It holds:

- `IOperatorSurface` and its two real implementations, `NativeOperator`
  over the binding and `SnapshotOperator` over a published snapshot. The
  sample surface goes; a surface that invents data is not a surface.
- The scope tree: one `Beneath`, one rollup (`Fine` or `Holding`, ADR-0041),
  one *worst leaf beneath a scope* with its evidence and age.
- Runtime discovery, one rule for every surface: the configuration's
  `Xmip:RuntimeLibrary`, else `XMIP_RUNTIME_LIBRARY`, else the library
  beside the executable. The language server keeps the same rule in Rust.
- A status said in English, once.
- The configuration document, read once: TOML, the same reader everywhere.

`Xmip.Gui` keeps the Razor and nothing else. The CLI, both hosts and the
PowerShell module reference `Xmip.Surface`.

### 2. Holding says why, where it is

Wherever a surface shows a Holding scope — the cluster banner, a stage tile,
a node row, a branch in the drill-down — it shows, beside the word, the
worst leaf beneath that scope and that leaf's evidence, worst first when
several are equal. The word alone is not a state an operator can act on.
There is no *follow the error* button: the operator drills down, or reads
the audit. A leaf shows its own evidence, as it does.

### 3. The web GUI monitors, and the surface is chosen

The web host reads a surface and renders it. It does not load the runtime
to start a node, and it shows no Pause or Resume: its role is Observer, and
that is not configurable. The desktop host monitors and configures, as
ADR-0014 says. Which surface a host reads — native over a library, or a
snapshot at a path — is stated in its `xmip.gui.toml`; nothing is chosen by
finding a file in the temp directory. A snapshot path that does not exist is
said so on the page, not silently replaced.

### 4. Paused is a mood

A paused scope is `Paused` (ADR-0041), reported by the surface as such and
rendered from the mood. No surface matches an evidence string to learn a
state.

### 5. The CLI is the executable ADR-0014 describes

`xmip` finds the runtime by the one rule and takes no library path as an
argument. It emits text for a person and, with `--json`, JSON for a program;
`--follow` emits JSON Lines as clause 10 says. It has tests, in
`Xmip.Cli.Test`.

### 6. Every surface is tested and verified in its own language

`Xmip.Surface.Test` covers the scope tree, discovery, the snapshot surface
and the English. `Xmip.Cli.Test` covers the commands. The extension's
TypeScript is compiled and linted by the landing gate, the way its Rust is
tested. A repository's workflow runs its own language's verification.
Template remains — platforms the project does not target, the layout and
reconnect pages the template wrote, the sample path that names a directory
that does not exist — go.

## Consequences

- One tree, one rollup, one discovery rule and one English, so a fix in any
  of them reaches every surface at once and the surfaces cannot drift, which
  is the guarantee ADR-0014 exists for.
- The web GUI becomes what its amendment says it is. Anyone who relied on
  starting a node from the web page starts it from the desktop or the CLI.
- `Xmip.Surface` and its tests land in `xmip-core-abi`; `cli`, `gui` and
  `powershell` gain a reference and lose their copies. `gui/vscode` shares
  its fixture from `gui/samples` and gains a TypeScript gate.
- The board answers the owner's question without a click.

## Amendment, 2026-09-14: the row, the figures, the two acts, and what was declined

`Xmip.Surface` gains three shapes every surface renders and none invents.
`Figures` is the six counted things at a scope in the order every surface says
them — Streams, Messages, Journeys, bytes, Retrying, Failed (ADR-0027 clause 5
and its amendment of 2026-09-14) — with an unpublished figure absent rather
than zero. `ScopeItem` is one row of the tree: the name, the mood, the worst
leaf's severity and evidence (clause 2), and the figures. `ScopeOperation` is
what came of a `ScopeAction`, and a `ScopeAction` is Pause or Resume, the two
acts the boundary carries. The executable renders them as `xmip measure`,
`xmip list`, `xmip show`, `xmip pause` and `xmip resume`; the PowerShell
module emits them as objects from `Suspend-XmipScope` and `Resume-XmipScope`,
both with `-WhatIf`. Retrying and Failed are figures, not Activity: ADR-0032
owns that word for the items behind a count.

Declined the same day, from the same proposal:

- **Start, stop and restart of a scope, on every surface.** ADR-0027: the
  thing that watches must not be able to stop the thing it watches, stated as
  a property of the boundary, and the boundary has no such call. A surface
  stub that answers "unsupported" is a promise the record forbids.
- **A PowerShell drive over the scope tree.** No record asks for one; the
  BizTalk provider is ADR-0014's example of a surface that drifted; objects on
  the pipeline are the PowerShell shape (ADR-0014 clause 10).
- **A prompt segment of five counts in five colors in place of the mood.** The
  prompt says the mood — `[Xmip holding]` — because clause 2 puts the mood and
  its reason first, and a count without the word beside it is a number, not a
  fact.
- **Received, Processed and Sent as the names of Streams, Journeys and
  Messages.** ADR-0027 clause 5 keeps those three words apart on every page;
  renaming them at the surface is where BizTalk's vocabulary would have come
  back in.

Proposed by an assistant session on 2026-09-12; reviewed and settled by the
owner with the assistant on 2026-09-14.

## Amendment, 2026-09-14: the three views, the exact scope, and the node

The owner's rulings of the same evening, on what the surfaces show and from
where. Each is a consequence of clause 1, one model every surface renders,
applied to the GUI as it stands.

1. **Three views: Configuration, Monitor and Topology.** The owner named
   them later the same evening — first as Cluster, Monitor and Topology,
   then, at the end of the night and finally, as *the classic Configuration
   (tree), Monitor as it was but better, Topology (new)* — and the naming
   supersedes the first draft of this ruling, which had called the third
   view a static drill-down. **Monitor** is the default view, the board
   that follows receive → process → send and moves as the cluster moves.
   **Configuration** is the classic tree: the whole cluster open — Cluster,
   Node, receive → process → send, every Receive Location, Xmip Process and
   Send Location, the technology beneath — in configuration order, holding
   still so an operator can focus on the problem at hand; from every row it
   reaches the configuration behind the scope and the binaries a node runs
   (the modules loaded, ADR-0025). Landed the same night as a first cut in
   the web GUI, `/configuration`, first in the top bar: the tree, every
   branch open, each row linking to the monitor's drill at that scope; what
   the surface does not publish, the declaration and the binaries, is
   queued with the native boundary's topology. **Topology** is the overview of the
   cluster, its own communication drawn (ruling 3), and from it an operator
   navigates to another Xmip cluster when allowed to. The shape of all three
   is ADR-0027's scope tree, which the boundary already publishes.
   **Drilling down is what every surface is for** — the CLI, the PowerShell
   module and both GUIs exist to solve a problem, and each of them drills
   from the cluster to the leaf that explains the mood; a surface that
   stops short of the leaf has stopped short of its purpose.
   In the playground a roll is a cluster (ADR-0028), so a second cluster to
   navigate to is a second roll with a name — the owner's example,
   `Start-XmipTest -Suite Playground -Test RoundTrip -Nodes R1, P1, S1, O1
   -OnlineNodes O1 -SuiteName SN2`. The owner withdrew the name the same
   evening — *my naming was wrong here* — since `-Suite` is already
   Playground or Estate and the thing named is a cluster: the parameter is
   **`-Cluster SN2`**, true to ADR-0028. Landed the same night: a roll's
   scope root is `xmip:///<cluster>`, its nodes hang under it, it publishes
   to `<cluster>-snapshot.toml` and keeps its own scratch, so two rolls are
   two clusters side by side, each with its own web monitor
   (`Start-XmipTest -Cluster C2 -PassThru | Start-XmipWeb -Url ...`).
   One page navigating between them is what stays queued.
   What the playground topology draws is what the owner is after, in his
   words: **the fleet, the shared store, one process per node**. For the
   tests, each OS process simulates a node on a different computer, and that
   is good enough; a firewall and a reverse proxy between them come later.
2. **Every view names the exact scope.** The monitor, the topology and the
   drill-down say which Receive Location, which Xmip Process and which Send
   Location, never only the transport and the contract beneath them. The
   playground drills stage → transport → contract because its scopes are
   built that way (ADR-0028); that is the playground's shape, not the
   product's. A node run from configuration (Suggested order, item 1) has
   Locations and Xmip Processes by name, and the views show those names.
3. **The topology shows Xmip's own communication.** The page's statement
   that Xmip does not infer application relationships from sockets or health
   records is wrong as a rule: the relationships between a Receive Location,
   the Xmip Process a Subscription starts and the Send Location it feeds are
   configured, and between nodes of a cluster they are observed. Both are
   the topology's to draw, beside the infrastructure endpoints it aggregates
   today. Nothing is inferred from a socket; what is configured is read and
   what is observed is published, which is clause 1 again.
4. **Drill to configuration, and change it by role, on the web as on the
   desktop.** From any scope, the drill-down reaches the configuration that
   declared it. An Operator may change it there (ADR-0009: Observer watches,
   Operator also configures), and a principal who is also a Developer can
   open the specific point's configuration from the scope — the declaration
   behind the row, reached from the row. The owner, later the same night:
   the drill-down goes *through* the configuration, and a link from any
   other view — a row on the monitor, a node or a link on the topology —
   ends at the view of the actual configuration, not at a summary of it.
   **The web GUI offers every role,
   not Observer alone.** ADR-0014's amendment of 2026-09-05 made the web
   monitor-only because a page in a browser cannot read a file on disk or
   load the native library; the owner rules that the limit is the browser's,
   not the web GUI's. Server-side Blazor invokes the executable on its
   server, locally or over remoting, exactly as clause 11 of ADR-0014 says
   every GUI does, and a node's configuration is on the node, reached the
   same way. The web is monitor-only no longer; ADR-0014 and ADR-0009 are
   amended today to say so.
5. **The node is in the prompt.** Remote operation rides PowerShell
   Remoting and SSH (ADR-0014 clause 6; ADR-0027), and a session on another
   node must say so where the eye rests. The prompt segment names the node
   beside the mood — `[Xmip R1 holding]` — whenever the session is remote,
   so an operator on more nodes than one never acts on the wrong one.
6. **Nodes are named for what they do.** A node in an example, a fixture or
   a playground roll is R1, P1, S1 and their kin — the stage it carries and
   a number — not alpha, beta and gamma. A name that says the role reads at
   a glance in a prompt, a row and a drill-down; a Greek letter says nothing.
   The playground's examples and fixtures are renamed the same day; the
   playground still runs every stage on every node, so the letter there is
   what the node is for, not what it is limited to.
7. **Nothing on a page starts anything, and the page's own words when the
   circuit drops.** No browser starts a web server: `Start-XmipWeb` starts
   the web host, detached, and opens no browser; a page that appears to
   start a server was started by a tool outside the estate. When the
   circuit between the page and its host drops, the page says so in the
   estate's words and style — *Reconnecting to the web monitor*, then
   FAILED or REFUSED with a plain reload — not in the box blazor.web.js
   draws when no element of the host's own is there. Clause 6 removed the
   template's dialog; this puts the estate's in its place, without a script,
   since the estate keeps JavaScript to the VS Code extension. Landed the
   same day.

8. **The owner names the cluster; a test may spawn nodes, never a
   cluster.** The owner, later the same night, on an assistant's plan to
   default a roll's cluster to a name of the tool's choosing: *I name the
   nodes, their roles are by configuration, I name the clusters. I start
   them when I want to.* And on the fleet: *by tests, you may spawn nodes,
   not cluster, when needed.* So `-Cluster` is required for a roll and the
   roll binary refuses without `XMIP_PLAYGROUND_CLUSTER`; the estate module
   invents no cluster name, and the built-in *playground* cluster is gone.
   The level's own numbered fleet stays (ADR-0028): a test spawns the nodes
   it needs, and that is the tests' business only — in a real environment
   nodes are spawned by the orchestrator, Kubernetes, .NET Aspire or their
   kin, never by Xmip; the tests' fleet is System Processes on one machine,
   for now (the owner, the same night). Ruling 6 is read in that light: R1 is the name the owner gave
   a node, not a role — what a node does is its configuration (ADR-0009),
   and in the playground every node runs every stage. Landed the same
   night.

Landed the same day: the renaming (6), and the first of the topology (3) —
the playground's fleet publishes its nodes, its shared store and each node's
exchanges under `[topology]` in the snapshot the web GUI reads
(`test/playground/src/topology.rs`), so the view is no longer empty over a
roll. Recorded and queued, not built: the third view (1), the exact names
(2), the topology over the native boundary (3), the configuration drill (4)
and the prompt (5), as Suggested order item 3 in
`doc/planning/open-problems.md`.

## Alternatives considered

**A `Xmip.Surface` repository of its own.** Rejected for now: it would be a
fifth .NET project with one consumer group; the ABI repository already hosts
the binding and the surfaces already depend on it. If it grows a life of its
own, ADR-0016 says how it moves.

**Keep `SampleOperator` for demos.** Rejected: a surface that invents
records is how a stale or fake board goes unnoticed, which is the failure
this record is correcting. A demo reads a published snapshot.

## Provenance

The priority and the ruling on the button are the owner's, 2026-09-11. The
survey, the library, its home and the clauses are the assistant's drafting
of *consolidate, refactor and re-engineer if needed*.
