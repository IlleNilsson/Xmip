# ADR-0052: The operator surfaces share one model

- Status: Accepted
- Date: 2026-09-11
- Related: ADR-0014 (the operator surfaces; amendments 2026-08-26, the ABI
  is the interface into Xmip; 2026-09-05, the web GUI monitors; 2026-09-09,
  the .NET binding is one project in xmip-core-abi; 2026-09-10, the
  configuration tool has two faces), ADR-0027 (the operator boundary;
  amendments 2026-09-24, section 7's rules and section 8's publication
  reader), ADR-0041 (health is a mood and does not propagate; its color name
  corrected 2026-09-24, its rollup exported the same day), ADR-0044 (a
  technology shares through its capability), ADR-0056 (a node declares what
  it can do; its copies corrected 2026-09-24, its evidence and run entry
  moved to the node crate the same day)

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
  *(Amended 2026-09-24: it does not. The rule is written once, in
  `RuntimeLibrary`, and the language server is told its library — the
  amendment "one implementation, and the surfaces call the runtime's
  exports".)*
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
   (`Start-XmipTest -Cluster C2 -PassThru | Start-XmipOperationWeb -Url ...`).
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
6. **A name in an example is only an example.** The playground's examples and
   fixtures were renamed the same day, from alpha, beta and gamma to R1, P1
   and S1, on the assistant's argument that a name saying the stage reads at
   a glance in a prompt, a row and a drill-down where a Greek letter says
   nothing. The renaming happened and is what landed; the argument did not
   survive. The owner struck it on 2026-09-20, of nodes and of clusters
   alike — *Rn, Pn and Sn are arbitrary node names*; *C1 and C2 are not
   roles, they are arbitrary cluster names, there may be one or more
   clusters* — and ruling 8 below had already glossed it that way the same
   evening. So the rule this ruling leaves behind is the narrow one: an
   example needs a name, any name a file can carry will do, and nothing in
   Xmip reads one. What a node does is the capability it declares
   (ADR-0056), and the playground runs the stages a node declared, never the
   stages its name suggests. Where the estate shows an example it varies the
   spelling on purpose, so that none of them reads as the shape a name is
   supposed to take.
7. **Nothing on a page starts anything, and the page's own words when the
   circuit drops.** No browser starts a web server: `Start-XmipOperationWeb` starts
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

## Amendment, 2026-09-15: the five figures join the prompt

The amendment of 2026-09-14 declined *a prompt segment of five counts in five
colors in place of the mood*. The owner reaffirmed the counts on 2026-09-15:
*the PowerShell prompt should reflect `Receive`, `Process`, `Send`, reTries and
Failures, like posh-git does for Git repos.* Reaffirmed, it is his decision,
and the objection is met rather than overruled: the mood stays first and in
its color, so clause 2 holds, and each count carries its letter, so it is a
fact with the word beside it, not a number alone. The segment is
`[Xmip holding R12 P11 S10 T1 F0]`: R, P and S are what the three stages
count — Streams, Journeys, Messages, `ScopeTree.CountedAt`, the same figures
the board's tiles say — T is Retrying and F is Failed, the two outcome counts
of the amendment above; bytes stay off the prompt. A figure the publisher has
not published is a dash, never a zero. The letters light only when the count
is above zero, T in the stressed color and F in the failed one. Built the
same day in `Xmip.PowerShell` (`PromptMonitor.Render`), composing with
posh-git as before. Ruling 5 of the amendment above, the node in the prompt
when the session is remote, stays queued.

The owner, later the same day, on seeing it: *we do not need the mood. R, P,
S, T, F in colors from red, yellow and green will solve that. Space is
precious on a console line, so the mood shall not be spelled out; colors.*
So the segment is `[R12 P11 S10 T1 F0]` and no word: a stage letter is
green, yellow or red by the worst leaf on that stage — Fine green; Paused,
Working and Stressed yellow; Exhausted and Done red — T yellow and F red
when above zero, green otherwise, and gray where nothing is published.
Clause 2's mood-first still holds on every surface with room for a word;
the prompt has none, and its color is that mood. Built the same day.

## Amendment, 2026-09-15: a surface is told, it does not ask

The owner, on a proposal from outside the estate to move the surfaces to
events over SignalR: *whenever eventing, SignalR can be used by CLI, UI, GUI,
it should. Polling is not preferred unless really needed.* Recorded as the
rule for how a surface learns that something changed, and it changes nothing
about what a surface reads: the snapshot stays the truth (ADR-0027), the
change feed says only that a new one exists.

- **Told, not asked.** `WatchAsync` is the one change feed every surface
  follows, and it is signalled: the native boundary blocks in
  `xmip_wait_change_v1` on a revision, and a published snapshot file is
  watched by the file system. The two-second loop in `NativeOperator` is
  the fallback for a runtime that cannot signal, kept for a rolling upgrade
  and for nothing else; the twenty-five millisecond settle after a file
  event is a debounce, not a poll.
- **SignalR carries it across a network.** When a surface follows a host on
  another machine — the CLI, the PowerShell module or a GUI following a web
  host that follows a node — the change feed rides SignalR, which the web GUI
  already speaks as server-side Blazor. Built the same day, on the owner's
  *do it*: `RemoteOperator` in `Xmip.Surface` is the third implementation of
  the one interface, chosen by `Surface = "remote"` and `Url` in any host's
  document or by `xmip --remote <url>`; `Xmip.Surface.Relay` is the served
  half, `SurfaceHub` at `/surface` answering what the web host's own surface
  answers and `SurfaceRelay` pushing that host's change feed to every
  connected remote surface. The web host serves it; the CLI, the PowerShell
  prompt and the desktop follow it; `validate` stays local because it asks a
  runtime. Proved against a hub on a loopback port in `Xmip.Surface.Test`:
  the same records over the wire, and a notice told, not asked, when the
  host's file advances. The two acts cross the wire as they cross the
  desktop, by role once ADR-0009's gate lands.
- **Polling only when really needed**, and then the record says why at the
  loop.

## Amendment, 2026-09-15: the index — a publication is read once, as its tree

The owner, on serious slowness in the GUI, the CLI and the PowerShell prompt:
*it has to be a better way, go find it out.* Found: every surface filtered
the whole publication again for every question. A board render asked the
runtime for the health beneath the root, the branches beneath the focus,
each stage, each node and the figures, and each answer walked eleven
thousand records, splitting every scope into segments on the way; over the
native boundary each answer first cloned the whole publication under the
lock the publisher needs, eight times a render; over a snapshot file the
two megabytes were flattened into sixty thousand configuration keys every
second. The fix is not faster filtering. It is none.

- **`ScopeIndex`** in `Xmip.Surface`: a publication as the scope tree
  ADR-0027 describes, built in one pass — every scope with its worst leaf,
  its rollup, the leaves beneath it, its children worst first and its six
  figures summed upward. Immutable; a new publication is a new index, and
  the change feed says when. Health, figures, branches, rollup and nodes are
  lookups in it.
- **Every surface answers from its index.** `IOperatorSurface.Index()` is
  the one call. The snapshot surface builds one per file write, from the
  Tomlyn document itself and no longer from a configuration; the native
  surface reads the health beneath the root across the boundary once per
  revision of the runtime's clock and keeps the index until the clock moves;
  the remote surface fetches once per notice. `ScopeTree.Beneath` compares
  by segment without splitting.
- **The runtime hands out a handle, not a copy.** `PUBLISHED` holds an
  `Arc<Snapshot>`; a call answers from the handle it took, and a
  publication, once published, is never changed in place.
- **A page reads the index and renders what it shows.** The Cluster page
  reads once per publication and virtualizes its long list; the
  Configuration tree is the index's branches in configuration order; the
  prompt reads the root's rollup and figures.

Proved in `Xmip.Surface.Test`: the index says what the record-by-record
helpers say, and it indexes a Playground's eleven thousand leaves well within
one render. Built the same day, on the owner's word.

## Amendment, 2026-09-18: a published file is flushed, and the executable chooses too

The owner, three days after the prompt first showed figures: *the status
prompt for PowerShell and CLI if possible still does not work.* It said
`[Xmip unavailable]` while the C1 snapshot lay where the document said,
because that snapshot, its history and its activity file were each the
right length and nothing but zeros: a hard stop on 2026-09-16 came after
the Playground's rename and before the data reached the disk. A rename is
journaled and file contents are not, and `write_atomic` had only written
and renamed. Two consequences, built the same day:

- **A publisher flushes before it renames.** `write_atomic` in the
  Playground writes the sibling temp file, flushes it to the device, then
  renames it over the target. A reader sees the previous file or this one,
  never a torn one and never an empty one; this is what *atomic* meant in
  clause 3 all along. Any Xmip publisher that writes a snapshot follows the
  same order.
- **The executable's document chooses its surface, as every other host's
  does.** Clause 3 and the amendment of 2026-09-15 said *any host's
  document*, and `xmip.cli.toml` was read for `RuntimeLibrary` alone; the
  executable could follow a library or `--remote`, never a snapshot. Now
  `SurfaceOpen` reads the same `[Xmip]` keys — `Surface`, `RuntimeLibrary`,
  `Snapshot`, `Url` — and the line wins over the document: `--remote`, then
  `--runtime`, then what is written. As shipped, `xmip.cli.toml` follows
  the C1 roll, the same file the PowerShell prompt follows, so `xmip show
  xmip:///C1` and `[R… P… S… T… F…]` say the same thing from the same
  publication. `validate` still asks a runtime. Proved in `Xmip.Cli.Test`:
  the precedence, with no surface asked to answer.

## Amendment, 2026-09-18: the prompt follows the roll its session started

The owner, the same evening: *I still can't get the prompt to show status
while running test.* The roll was cluster CC1, publishing
`CC1-snapshot.toml` every tick, and the prompt followed `C1-snapshot.toml`,
the one file the shipped document names; it sat frozen on another cluster's
last publication. Clause 3 stands — a surface is stated, never guessed — and
the operator had stated it, to `Start-XmipTest -Cluster CC1`, which knew
the file and told nobody. Now it tells the prompt: where the PowerShell
module is loaded in the session, `Start-XmipTest` calls
`PromptMonitor.Follow` with the snapshot its roll publishes, and the
observer restarts on that file; a replaced observer can no longer write the
segment. Nothing is loaded that was not, and a session without the prompt
is untouched. A roll started elsewhere is still followed through the
document. Proved in the module's tests: the segment follows a snapshot the
session names over the one the document ships.

The owner, on seeing it work: *I asked for the same kind of output as
posh-git*, and *that Xmip is connected is obvious, as it is for posh-git, if
the prompt shows it.* So the segment sits where posh-git puts a
repository's state, after the path and before the closing `>` —
`D:\Repos\Xmip [main] [R12 P11 S10 T0 F0]>` — composed into whatever
prompt is in force, and it had stood in front of the whole prompt. And
where there is nothing to show there is nothing on the line: connecting,
unavailable and not configured are the absence of the segment, as posh-git
shows nothing outside a repository. One word remains, `[Xmip
misconfigured]`, for a document that names a surface this build does not
know, because that is the operator's to fix. Clause 3's *said so on the
page* still holds for a page; a prompt has no room to say it.

And on `[R5,317 P60 S60 T– F–]` over a live roll: *T and F do not need to
be there if there are none.* So T and F are on the line only when something
is retrying or has failed, `[R5,317 P60 S60]` otherwise, and they are
yellow and red when they are there; a zero, and a count nobody published,
are both nothing on the line. And a colon stands between a letter and its
number wherever there is a number to present, `[R:5,317 P:60 S:60 T:3 F:1]`,
by the owner's word the same evening; a figure nobody published keeps its
dash and takes no colon.

And last that evening: *I like it, but I like the posh-git style better.
The color, light blue, when things are fine, square, and the hamburger
symbol aft when things are fine.* So the segment wears posh-git's clothes:
yellow brackets; the cyan posh-git gives a branch in step with its remote
for a stage that is fine, where the prompt had used green; and posh-git's
own `≡` at the end, in cyan, when every stage is fine and nothing is
retrying or failed — `[R:5,317 P:60 S:60 ≡]` — gone the moment anything is
not. Yellow and red stay what they were. ADR-0041's one color name per mood
holds on every surface with room for a color of its own; the prompt sits
beside posh-git and takes its palette.

Then its order and its numbers: *posh-git has the hamburger after a branch,
let's use that. If the Xmip prompt is at a node, write node name +
hamburger. Xmip is also dealing with numbers greater than integers, so
incorporate K, M, G so the prompt won't go wild.* So the segment reads as
posh-git's does, `[main ≡ +0 ~1 -0]` there and `[R1 ≡ R:5.3K P:60 S:60]`
here: what the prompt is at, the sign when square, the counts. What it is
at is the last name every published scope shares — a node's own
publication shares its node, a cluster's only the cluster — in the color of
the worst stage, and a segment that is only a kind, the Playground's
`node`, names nothing. A count is as it is below a thousand and then in K,
M and G, one decimal below ten of a unit.

And, since 5.3K is 5.3K for a long while: *if a value in K, M, G or higher
rises or lowers, let's paint it hotter or icier.* The letter keeps the
mood's color and the number takes the trend's, against what the same
observer published last: orange where it rose, magenta where it rose by a
tenth or more, a cool cyan where it fell, blue where it fell by as much,
and the mood's own color where it stands still or was not published before.
A count below a thousand is written in full, shows its own movement, and is
not painted. Red stays the mood's alone: hot was dark red for an hour and
is magenta, because on a console the two reds read alike and a hot number
must never be mistaken for a stage that is done. The observer remembers one publication and the
renderer stays pure; the two are two files since the day they reached the
length one may be.

## Amendment, 2026-09-19: a cluster rolls once, and a reader keeps what it read

The owner, past midnight, on a prompt that showed nothing at all: *need
more, or something is wrong.* Something was. Three rolls ran as cluster CC1,
started from three consoles, each with its own three nodes and all
publishing to the one `CC1-snapshot.toml`; a surface saw 803, 2,259 and
11,499 leaves in turn. And the prompt was blank because one read had
collided with a publisher: on Windows a file being renamed over answers a
reader with a sharing violation or with *access denied*, the second is not
an `IOException`, the snapshot surface did not catch it, and the prompt's
observer ended on any exception and stayed ended.

- **A cluster rolls once.** A roll is a cluster and two rolls are two
  clusters (ruling 1 of 2026-09-14), and nothing held anyone to it.
  `Start-XmipTest` now refuses a cluster name that is already rolling, says
  REFUSED with the pid that holds it, and names the two ways on: stop it, or
  name another cluster.
- **A reader keeps what it read last through a read that collides.** The
  snapshot surface treats a file it could not open as a moment, not as an
  empty estate: the last publication stands and the next question reads
  again. A file that is not TOML is still an empty estate, said so.
- **One bad publication is one missed tick.** The prompt's observer keeps
  observing and the segment keeps what it said.
- **A publisher's temporary file is its own**, named for its pid, so two
  processes publishing to one path — refused now, and still possible for a
  roll started by hand — do not write into each other's half-finished file.

## Amendment, 2026-09-18: the Configuration view drills to the problem, and what the Topology lacks

The owner, on the web GUI: *Configuration tab, nice with icons with
severity, missing drilldown to the problem area. Topology: observed only
shows fleet to shared store. Not between receiving nodes, processing nodes
and sending nodes. Does not show sending and receiving endpoints. Does
nothing of use.*

- **The tree drills to the problem.** Ruling 1 of 2026-09-14 says a surface
  that stops short of the leaf has stopped short of its purpose, and the
  first cut of `/configuration` did: a troubled branch said how many lay
  beneath it and linked only to the monitor. Now a branch that is not fine
  names the leaf that explains it, with its evidence, and carries a
  *problem* link to that leaf's row; the branches on the way to it stand
  open however deep, so the link lands on something visible, and the row it
  lands on is outlined. The cluster's own row does the same. No script: the
  browser's details element and a fragment, as before.
- **Three points to drill from, and nothing else.** The owner, the same
  evening: *the web solution has to be simple, drill down from three
  points, configuration, monitor and topology. No need for Configured +
  observed. Topology shall always be Configured + observed.* So the
  Topology's switch between configured, observed and both is gone and the
  picture is always both; origin is still said on what is selected and is
  never a filter. And a scope reached in one view leads to the same scope
  in the others, written in one place (`ScopeLink`): a Configuration row
  to the Monitor's drill, the Monitor's drill to the Configuration row, a
  node or a link selected on the Topology to both. Every Configuration
  row, branch or leaf, is a place a link can land. Ruling 4 of 2026-09-14,
  built for what the surfaces publish today; the declaration behind a row
  stays queued with the native boundary.
- **The Topology draws all there is, and that is the finding.** A Playground
  node runs the same two scenarios as every other, against one shared
  directory; R1, P1 and S1 are names, and a name says nothing about a role
  (ruling 8). There is no traffic from a receiving node to a processing
  node to a sending node, and no endpoint outside the cluster, so there is
  nothing of that kind to publish, and a surface that invents it is not a
  surface (clause 1). Beneath that sits `open-problems.md` problem 17, *how
  does work reach another node*, lean A and undecided: the product itself
  does not yet hand work between nodes. What the owner asked for is
  therefore a Playground that rehearses a staged path — endpoints outside,
  a stage per node by configuration, and the hop between nodes — and that
  waits on his word on problem 17, asked the same evening. Recorded and
  queued, not built.

## Amendment, 2026-09-19: the Topology is cluster, nodes, receive, process, send

The owner, on the Topology over a roll: *Fleet is what I see in topology when
running test, I would like to see cluster, nodes, receive, process, send.*
What was an assistant's was borrowing the word for a group of the rig's node
processes, which is a cluster and was already called one; that borrowing is
what ADR-0028 retires the same day. Fleet itself keeps its own meaning as a
domain Actor — ADR-0007's communication domain model opens its examples with
*Fleet owner → Ship owner → Ship → Captain → Crew*, and
`doc/architecture/runtime-model.md` says the recursion *lets one architecture
serve a fleet operator and a sensor on a bus* — so the claim first written
here, that the word appeared in no record of the estate's vocabulary, was
wrong and is corrected. Where an earlier amendment of this record says Fleet
of the rig's processes, read *the cluster's nodes*.

- **What a roll publishes.** The cluster (`kind = "cluster"`, scope
  `xmip:///<cluster>`) holds its nodes (`node`); a node holds the stages of
  the message path it runs (`stage`); a receive or a send stage holds one
  endpoint per transport it reported on (`endpoint`, the transport's scope
  beneath the stage). The nodes' rollup is the record of the branch they
  hang under, `xmip:///<cluster>/node`, which the scope index shows as that
  branch's own and never as a node beside them. The shared store,
  `xmip:///<cluster>/shared`, is drawn only when a node ran a test over it.
- **What runs between the nodes.** The finding of 2026-09-18 stands
  answered for the rig: a node runs the stages of RoundTrip it declared and
  hands each pair on, receive to process to send, between real processes,
  and every delivered handoff is a hop on a link (`send-receive`, protocol
  `handoff`, volume the hops, mood the worst leaf at either end); the hop
  carries the stage at either end, so the link is drawn without reading a
  name. `open-problems.md` problem 17 records that this rehearses option A
  in the rig and rules nothing for the runtime.
- **The run says what it was started with.** The snapshot carries `[run]` —
  tests, nodes, what each was started with, which are online, the level —
  `Xmip.Surface` reads it as a `RunHeader`, and the web GUI says it in one
  line at the top of all three views. The prompt is unchanged.
- **Ruled the same day: a node carries the roles suitable for its purpose.**
  Asked, the owner: *Rn, Pn, Sn are nodes that carries roles.* The
  assistant wrote that back as one role to a node, and was corrected the
  same hour: *a node carries roles suitable for its purpose.* So a node is
  not fenced to one stage: the roles it carries are the ones its purpose
  needs, which is what the rig does when a node is started declaring
  `receive`, or `process,send`.

  The assistant read one thing more into that than the owner had said — that
  the letter of `R1` names the node's purpose, and so that a name the owner
  gives says something — and wrote it here on 2026-09-19 as superseding the
  gloss on ruling 8 of 2026-09-14, *R1 is the name the owner gave a node, not
  a role*. The owner struck that reading the next day, 2026-09-20, on both
  halves of it: *C1 and C2 are not roles, they are arbitrary cluster names,
  there may be one or more clusters*, and *Rn, Pn and Sn are arbitrary node
  names.* So the gloss of 2026-09-14 was never superseded and stands: a name
  is the operator's, it says nothing, and nothing in Xmip reads one. What the
  ruling of 2026-09-19 did settle — a node carries the roles its purpose needs
  — stands as written above, and ADR-0056's amendment of 2026-09-20 is where
  the rule lives now. The rest of ruling 8 was never in question: he names the
  clusters, and a test may spawn nodes and never a cluster.

  What the rig does today, for the owner to keep or widen: **a node is
  started with a declared capability and serves the stages it declared** —
  `--can receive`, or `--can process,send` for a node whose purpose needs
  both — and the topology draws a node's stages from the capability record
  it publishes (ADR-0056). `-NodeCapability @{ alpha = 'receive' }` states
  that capability, and since 2026-09-20 it is the only thing that does:
  `Start-XmipTest` briefly read `R`, `P` and `S` as a shorthand at the
  operator's door, and the owner struck it — *Rn, Pn and Sn are arbitrary
  node names* (ADR-0056, amendment 2026-09-20). Nowhere in Xmip — this
  cmdlet, the roll, the cluster, a node, the topology, every surface — is a
  node's name read. A run of cluster Z8 over nodes called `alpha`, `beta` and
  `gamma` draws the same receive-to-process-to-send handoffs as one over
  `R1`, `P1` and `S1`.

  **The correction this paragraph records.** For one afternoon on
  2026-09-19 the assistant had the rig take a node's stage from the first
  letter of its name. The owner: *I know, so why do you break it!* The
  estate already held the model — ADR-0009, what a node does is its
  configuration; ADR-0022, placement must satisfy node capability; the
  deployment model, *any capable node may resume work if it can satisfy the
  required capabilities* — and ADR-0056 wrote down what a capability is.
  Configuration and capability decide; a name is not a criterion.

## Amendment, 2026-09-19: the roll is the test, the cluster is a process

The owner: *even clusters have to be spawned as processes during tests.*

Ruling 1 of 2026-09-14 and the amendment above say *a roll is a cluster*.
Read it now as *a roll is one cluster's test, and the cluster is a process
the roll spawns*. A roll still means exactly one cluster — `Start-XmipTest`
still refuses a name already rolling, and the cluster is still the owner's to
name (ruling 8) — but the roll no longer is the cluster.

Nothing a surface reads changes. The roll publishes `<Cluster>-snapshot.toml`
at the same path with the same shape: `[run]`, `[[records]]`, `[[counts]]`,
and the topology of this record's previous amendment — the cluster, its
nodes, their stages, an endpoint per transport, and the handoff links. The
cluster publishes its own half to `<Cluster>-cluster.toml` beside it, which
is the roll's input and no surface's. ADR-0028 and ADR-0053 carry the rest.

## Amendment, 2026-09-18: the executable is `xmip-cli`

ADR-0053: every System Process Xmip owns is named `xmip-<what>`, the
executable included, so that one line finds and stops them all. Where this
record says the `xmip` executable, read `xmip-cli`; an operator types
`xmip-cli health <scope>`. Nothing else about it changes.

## Amendment, 2026-09-19: a filter is a wildcard, and the wildcard is one

The owner, told that the filter convention had reached 8 of 137 PowerShell
parameters and neither of the other two surfaces: *Go ahead, as deep as you
can.*

**The rule is the estate's, not PowerShell's.** ADR-0059 clause 7 — a
parameter that selects among things that already exist takes a wildcard, one
that names a thing to create does not — was written for cmdlets, and reads as
a convention of the shell it was written in. It is not. It is a rule about
what an argument *is*, and it holds wherever an operator names a scope: at the
prompt, on the command line, in a box on a page. Clause 8 holds with it —
wildcards, never regular expressions — for the reason clause 8 gives: as a
regular expression `Rust.Style` also names `RustXStyle`, and as a wildcard it
is the name the operator typed.

**The matcher is shared, for the reason this record exists.** `ScopePattern`
in `Xmip.Surface` is `*`, `?` and literal everything else, case-insensitive,
matched over the scope's own path so that `C1/node/R*` and
`xmip:///C1/node/R*` are one pattern. Written twice it would have drifted
exactly as `Beneath` had drifted four ways before clause 1. `ScopeFilter`
beside it is that pattern applied to one publication — what matched, what
stands on the way down to it, and the one sentence a surface says about it —
so the three views narrow alike and none of them decides for itself what a
pattern means.

Where it cannot be `-like` exactly, the file says so and so does this record:
a character set (`[a-c]`) and the backtick escape are literal here, since no
scope the estate publishes carries either; and the scheme is read the one way
`ScopeTree` reads it, lower-case, so `XMIP:///C1` is a path and not a scope.
`*` crosses a `/`, as it does in `-like`.

**What each surface now filters.**

- **The executable.** `health`, `measure`, `list` and `show` take a pattern
  wherever they took a scope, and `pause` and `resume` act on each scope one
  names. What a pattern selects is the *topmost* scopes it matched: every
  command reads a scope and everything beneath it, so a child of a match would
  be said twice. Nothing is added together — `measure` over four scopes is
  four lines, because a sum over several scopes is a figure at a scope that is
  not in the tree, and `health` is one banner each, because a rollup over
  several would be the same invention (ADR-0041). `--json` carries the same
  answer in structure: `pattern`, `matched`, and the per-scope document a
  single read already emits. A pattern that names nothing is REFUSED, naming
  the pattern, what there is beneath the literal part of it and the source,
  and exits 1 — with `--json`, the refusal is a document too. `validate`,
  `probe` and `status` name a thing rather than select one, and take no
  wildcard.
- **The three views.** One filter box under the run line, the same control on
  each, applied when the operator presses Enter or leaves the box rather than
  on every keystroke — a view over eleven thousand scopes must not re-render
  under a typing hand. The **monitor** narrows its drill, its attention list
  and its node rows, and never its banner or its stage tiles: a filter that
  could make a troubled cluster look fine is worse than no filter. The
  **configuration** tree keeps the path down to every match, however deep, and
  stands open to it, and a row that matched shows its whole subtree. The
  **topology** filters nodes, and draws a link only where both of its ends
  survive, since a line to something hidden points at nothing. An empty box is
  everything; a pattern that matches nothing says so in the estate's words
  where the eye already is, and the topology says it where the picture was, so
  an empty canvas is never read as a cluster that publishes no topology. The
  desktop routes to these same pages and gains all of it.

**Judged, and the owner's to overrule.** The filter is each view's own and is
not carried between them or in the URL — a shared one would have to survive a
link, and no link carries it today. It applies on Enter, not per keystroke.
`pause` and `resume` take a pattern although they act: one act already reaches
everything beneath the scope it names (ADR-0027), so a pattern names several
subtrees rather than opening a wider one, and the exit is non-zero unless
every one of them applied.

**Not done.** The VS Code extension has no filter — its surface is its own and
its language is the one place TypeScript lives. The PowerShell module is
untouched: it already obeys, and widening the rule to the other 129 parameters
is a reading of each one, not a change of this kind. `--follow` re-matches its
pattern at every notice, which is built but proved only in the unit tests, not
against a live roll. ADR-0059 is the other agent's this session and was read,
not edited; the decision index was not regenerated, since nothing here changes
a record's In brief.

## Amendment, 2026-09-20: a face holds more than one cluster and says which

The amendment of 2026-09-14, ruling 1, landed two rolls side by side and wrote
down what it had not built: *from it an operator navigates to another Xmip
cluster when allowed to* — *one page navigating between them is what stays
queued*. That gap is what the owner met with `-Cluster C1` and `-Cluster C2`
rolling at once, and it was wider than a missing page:

- **The prompt reported C2 and said nothing of C1.** `Start-XmipTest` calls
  `PromptMonitor.Follow` on every start (amendment of 2026-09-18), so the last
  roll started won and the segment silently followed one publication of two.
- **The web views showed neither.** A host started without `-Snapshot` falls
  back to its own `xmip.gui.toml`, which names the native surface, and the page
  read `NATIVE — no runtime library at … · nothing recorded · 0 node(s)`.
- **The documented easy path refused itself.** `Get-XmipTestStatus |
  Start-XmipOperationWeb` piped two objects at a `[string]` parameter, and the
  second host found 5087 held.

**Nothing is added together, at any surface.** A cluster is a whole scope tree
with its own root (ADR-0027), and the amendment of 2026-09-19 already settled
what a surface may do with several of anything: a sum over several scopes is a
figure at a scope that is not in the tree, and a rollup over several is the same
invention (ADR-0041). Two clusters are two publications, side by side, and no
banner, tile, figure or prompt ever spans them. What is shared is the face.

- **`ClusterSurfaces` in `Xmip.Surface`** is one `IOperatorSurface` per cluster
  with a name above them — the shape chosen over one surface that answers per
  cluster, because that second shape would put a cluster argument on every call
  of clause 1's interface and invite exactly the rollup this record forbids.
  A cluster is named once, when the set is opened, from what its publisher says:
  `[run].cluster`, else the one first segment every published scope shares. Kept,
  not re-read — **a cluster keeps its name and its place in the chooser whatever
  becomes of its publisher**, and does not vanish from under the operator's
  hand. A roll that ends leaves its file, so its last publication still stands
  and reads as one (clause 3); a cluster whose surface answers nothing at all —
  the file taken away — is still in the chooser and says it has stopped
  publishing.
  **Two surfaces naming one cluster are REFUSED**, for the reason
  `Start-XmipTest` refuses a cluster already rolling: a face that held two could
  not say which it was showing. `Xmip.Surface.Test` proves the two, the one, the
  roll that ends mid-read and the refusal.
- **A host names its clusters in its document or on its line.** `Xmip:Snapshot`
  takes a path as before or a list — `Snapshot = ["…/C1-snapshot.toml", …]`,
  `--Xmip:Snapshot:0=… --Xmip:Snapshot:1=…`. A list wins over a path, because
  the two reach the same key from different sources and a line naming two
  clusters must not be quietly replaced by the one the shipped document names.
- **`Start-XmipOperationWeb` takes several and starts one host.**
  `Get-XmipTestStatus | Start-XmipOperationWeb` over two rolls is one host
  serving both. The parameter is `[string[]]`, still bound by property name from
  the pipeline, and the command gathers the pipeline in `process` and starts the
  host once in `end`; before, the body was one `end` block and a second object
  produced a refusal rather than a second cluster.
- **The three views say which cluster they are on, and move between them.**
  The cluster is in the address — `?cluster=C2` — so a link carries it, a reload
  keeps it, and two tabs watch two clusters. The chooser sits at the head of the
  **run line**, not on a line of its own: the owner has said twice that these
  views are crowded, there is a run line and a filter line already, and which
  cluster a view shows belongs beside what that run was started with. A host
  holding one cluster draws nothing new and writes the addresses it always
  wrote. Every link out of a view carries its cluster, since a link that dropped
  it would land on the other cluster's tree at a scope that is not in it; and
  moving cluster starts the drill and the filter over, for the same reason.
  `ClusterView` is where a page reads the set, names what it chose and follows
  that cluster's change feed — written once, as clause 1 asks, and it replaced
  the same watch copied into all three pages.
- **The prompt says there is more than it shows.** It still reads one
  publication, and the segment is untouched but for one thing: where the session
  named more rolls than the one it follows, the name carries how many it is not
  showing — `[C2+1 ≡ R:5.3K P:60 S:60]`, the count in the gray this segment
  already gives what it has no figure for. None beside is nothing on the line,
  as everything else here. The others are **named by the session**, never counted
  from files in a directory: `Start-XmipTest` says what is rolling when it
  follows the roll it started, and `Stop-XmipTest` says it again when one ends,
  so the count cannot outlive the cluster. Clause 3 holds — a surface is stated.

**The executable owes one thing, and it is not several clusters.** `xmip-cli`
answers one question at one scope and ends; it has no session to navigate and
nothing it could combine. What it lacked over two rolls was a way to say *which*
without editing `xmip.cli.toml`, so it gains `--snapshot <path>`, between
`--remote` and `--runtime` in the precedence the amendment of 2026-09-18 set,
and reads the first where a document names several. The desktop routes to the
same pages and holds its one surface as a set of one. The VS Code extension is
untouched: its surface is its own, and this changes nothing it reads.

**R, P and S are a rate, not a total.** The owner, the same day, on the segment
this amendment had just widened: *the CLI/PowerShell status number does not mean
anything over time. There has to be a logical cap on summarising the R, P, S, T
and F numbers or do a completely different prompt visualization.* Asked to
choose between a rate, a rolling window and a sparkline, he picked **the rate —
what is moving now**. A total is bounded by uptime and grows whatever happens; a
rate is bounded by throughput, and it can say `R:0/s`, **stalled**, which a
rising total can never say. That is the whole of the change.

- `[C1 ≡ R:1.2K/s P:240/s S:238/s]`. Everything else on the line is exactly as
  the owner left it — the K/M/G ladder, the hotter and icier trend, posh-git's
  yellow brackets and cyan, the `≡` when square, the node or cluster in front,
  T and F only when above zero. This changes what the number means, not how the
  line looks.
- **T and F stay counts.** A retry total and a failure total mean something and
  should be small, and they keep the rule they already had.
- **One publication is no interval and therefore no rate**, and that is the dash
  this segment already shows for a figure nobody published — never `0/s`,
  because on this line `0/s` means stalled and *not known yet* is not stalled.
  So does a figure that fell: a counter only falls where its publisher started
  over, and two publications of two runs are not an interval.
- **The calculation is `FigureFlow` in `Xmip.Surface`**, so a second face reads
  one rate rather than computing its own (clause 1). The clock is the reader's:
  a published snapshot carries no observation time for its counts, and the
  prompt reads at every notice, so the interval between two reads is the
  interval between two publications. A trickle is written `0.3/s` and never
  rounded to `0/s`, on the same *one decimal below ten of a unit* the K, M and G
  ladder already uses.
- **The trend colour still earns its place, and the judgement is stated rather
  than assumed.** Over a total it answered *is anything moving*, which the rate
  now answers outright; over a rate it answers a different question — *is the
  rate climbing or falling*, whether a cluster is speeding up or winding down —
  and no digit on the line says that, because `1.2K/s` is `1.2K/s` across a wide
  band. The rule that a number below a thousand is not painted holds for the
  reason it always did: 238/s to 241/s is visible in the digits.
- **The executable keeps totals, and this record says so rather than leaving the
  two surfaces silently different** (ADR-0014's amendment). An invocation is one
  sample, with no interval; a rate from a single reading would be the average
  over the publisher's whole uptime, which is the number being retired. With
  `--follow` there are samples, and clause 10's JSON Lines already carry each
  document's figures, so a program computes the rate exactly rather than being
  handed a rounded one. The web board is unchanged and was already right: its
  stage tiles have said *+412 last round · 240/s* since `English.Flow` was
  written, and the prompt was the one surface still saying a total.

**Judged, and the owner's to overrule.** `+1` glued to the name, rather than a
word or a second bracket, because space on a console line is precious and
posh-git's own `+` never sits against the branch name. The chooser on the run
line rather than in the top bar beside Configuration, Monitor and Topology,
because
the top bar is what a view *is* and the run line is what it is *of*. A cluster
the host does not hold falls back to the first rather than refusing, because a
roll that ended leaves links behind. And the surface relay serves the first
cluster alone: a remote surface reads one tree, and a tree of two clusters is a
scope in neither.

## Amendment, 2026-09-24: scope containment has two writers and one set of cases

**Struck by the owner, 2026-09-24:** *Code shall be uniquely placed, used by
others, whom in turn has unique code used by others. It is common sense.* Two
writers held to one set of cases are two copies, and a language boundary is no
reason for a second: the surface calls across it. The amendment "one
implementation, and the surfaces call the runtime's exports", below, replaces
this one; `src/scope-vector.toml` and both tests that read it are gone. What
follows is kept as it was ruled, so the record shows what was struck.

Open problem 25, row k: `ScopeTree.Beneath` read a scope by its path, the
scheme and the authority gone as ADR-0027 clause 3 says, while the runtime's
`observe` compared the whole text — so `xmip://edge-01/n/receive/a` was
beneath `xmip:///n` on a surface and not in the snapshot that paused it.

**The rule is `observe::Scope` in the runtime and `ScopeTree` on the
surfaces, both on purpose.** `Scope::contains` is what the snapshot and the
activity log answer by. Clause 1 keeps the scope tree in `Xmip.Surface`,
and it stays there: the owner, 2026-09-24, ruled that `ScopeTree` keeps its
own writing, because a surface loads no Rust library — the snapshot and
remote surfaces run with no runtime beside them, and a board compares
thousands of records at a time.

**One set of cases holds the two to one rule.**
`src/scope-vector.toml` in xmip-core-observe is the statement: each case a
scope, a candidate, whether one contains the other, and where useful the
path and whether it is the root. A test in `observe` reads it and
`ScopeTreeTest` in `Xmip.Surface.Test` reads the same file, copied beside
the test assembly from the estate checkout. A change to the rule is a
change to that file first, and fails whichever writer did not follow.

The cases cover the root in its four spellings, the authority on either
side, text without the scheme, a slash at either end, the lower-case scheme
(`XMIP:///C1` is a path), and a prefix of segments rather than of
characters (`n` does not contain `nx`). A query and a fragment are not
stripped on either side; nothing the estate publishes carries one yet, and
the cases record that behavior so a change to it lands in both at once.

## Amendment, 2026-09-24: the command line and PowerShell share, down the layers

The owner, 2026-09-24: *Force some love down the layers, CLI and PowerShell
shall share.* Clause 1 already said what the .NET surfaces share; an audit the
same day (open problem 25) found the executable and the PowerShell module
still writing several of the same answers twice, and the cmdlets short of
what the executable could do. Each moved to the lowest layer both already
reach — `Xmip.Abi` where the answer is the binding's, `Xmip.Surface` where it
is the model's — and each face now renders it; neither writes it.

- **Which surface an invocation reads**, the line over the document —
  `--remote`, `--snapshot`, `--runtime`, then the document, then the runtime
  rule — is `SurfaceChoice.Stated` over a `SurfaceLine`, and whether it
  answers is `SurfaceChoice.Answering`. The executable, the prompt and every
  cmdlet that reads a scope ask it. So `Get-XmipHealth`, `Suspend-XmipScope`
  and `Resume-XmipScope` take `-Remote`, `-Snapshot` and `-Library` as named
  parameters in the executable's order, `-Library` is no longer mandatory, and
  with none of them the module's own `xmip.powershell.toml` decides, as
  `xmip.cli.toml` decides for the executable: clause 1's one discovery rule,
  reaching the cmdlets at last. `Test-XmipNodeConfiguration -Library` finds
  its runtime by `RuntimeLibrary.Stated`, as `xmip-cli validate --runtime`.
- **What a scope argument selects** is `ScopeSelection`, moved out of the
  executable: the cmdlets' `-Scope` takes a wildcard over the scopes that
  exist, answered per topmost scope and never rolled up, and refuses one
  that names nothing with the executable's REFUSED sentence — the amendment
  of 2026-09-19 carried to the module it had left untouched.
- **The two acts** are `IOperatorSurface.Control` on every surface; the
  cmdlets' own pause and resume over the binding are gone.
- **A validation** is the `ConfigurationVerdict` `xmip-cli validate`
  renders; `Test-XmipNodeConfiguration` emits it in place of a shape of its
  own.
- **What a status code means** is `StatusMeaning` in `Xmip.Abi`, and a code
  the header does not define is `unknown` on both faces (the cmdlet said
  `Unknown`). **The two boundaries** are `AbiBoundaries`, and `Get-XmipAbi`
  now says the operator boundary too. **Whether a probed module conforms**
  is `ModuleProbe.Result.Complaint`, which the cmdlet now reports as the
  executable always exited on it.
- **A mood in text** is `English.Mood`'s word, lower case, on every command
  (`xmip-cli health` printed the enum's name); **a figure** is
  `English.Figure`'s, for the executable and the topology inspector alike;
  **nothing at a scope** is `English.NothingAt`'s sentence on both faces.

Each rule is tested once, where it lives — `Xmip.Surface.Test` and
`Xmip.Abi.Tests` — and the faces' tests call through it. What the estate
module (`Xmip/`, the script module) repeats of `Xmip.Surface` — a node's
declared capability, a snapshot read record by record, the worst leaf — is
not moved: no record says whether that module may load a built assembly, and
the question is the owner's (open problem 25). *(Moved the same day: the
script module loads the operator module and calls it — the next amendment.)*

## Amendment, 2026-09-24: one implementation, and the surfaces call the runtime's exports

The owner, 2026-09-24: *Code shall be uniquely placed, used by others, whom in
turn has unique code used by others. It is common sense.* And, against
collapsing everything into one place: layered, one home per concept. The
amendment "scope containment has two writers and one set of cases", above, is
struck by it. Each rule below has one implementation, in the crate that owns
it; the runtime's native library forwards it to the surfaces as a C export —
one call into the owner and no logic of its own (`xmip_operate.h` section 7,
ADR-0027's amendment of the same date); `Xmip.Abi` binds each export once
(`RuntimeRules`); and every surface calls it.

| Concept | The one implementation | Export | Callers |
|---|---|---|---|
| Scope containment, a scope's parts | `observe::Scope::contains`, `Scope::segments` (xmip-core-observe) | `xmip_scope_contains_v1`, `xmip_scope_parts_v1` | `ScopeTree.Beneath` and `Parts`, and through them `ScopeIndex`, `ScopePattern`, every face, and the script module's `Get-XmipTestResult` |
| The stage words, a declaration's parse | `node::Stage::WORDS`, `Stage::declared` (xmip-core-node) | `xmip_stage_words_v1`, `xmip_stage_declared_v1` | `ScopeTree.Stages`, `NodeCapability.Ordered`, and the script module's `ConvertTo-XmipNodeCapability`, its RoundTrip refusal and its roster reading |
| A mood's word, the mood a word names, its color's name | `observe::Health::word`, `named`, `color` (xmip-core-observe) | `xmip_health_word_v1`, `xmip_health_named_v1`, `xmip_health_color_v1` | `English.Mood`, `MoodOf`, `Color`, and through them `SnapshotOperator`, the GUI (`MoodClass`), the prompt (`SegmentRender.Traffic`), the command line and `Get-XmipTestResult`; the Playground's publisher, which is Rust, calls `Health::word` and `named` itself |
| The worst-first order | `observe::Standing` and `Standing::worst_first` (xmip-core-observe), which `Snapshot::health` sorts by | `xmip_health_order_v1` | `ScopeTree.WorstFirst`, `Worst` and `Branches`, `ScopeIndex` (one call per publication, every "which is worse" after it a lookup of the runtime's answer), the prompt's worst stage and `Get-XmipTestResult -Worst` |
| Runtime discovery | `RuntimeLibrary` (`Xmip.Surface`) | none: it finds the library the others are called in | every .NET surface and, through the operator module, the script module |

- **Every surface loads the runtime library**, a snapshot or a remote one as
  much as a native one. `RuntimeLibrary.Rules` loads it once per process: the
  library the surface's own configuration found (`Find`, `Stated`), else the
  rule with nothing configured, beside `Xmip.Surface`'s own assembly — beside
  the executable, or beside the module in PowerShell. A surface with no
  runtime says where it looked and how to put one there, and answers no rule
  from a copy. "A surface loads no Rust library", the reason of the struck
  amendment, is withdrawn with it.
- **Runtime discovery is the one rule a surface cannot ask the runtime for**:
  it has to find the library before it can call anything in it, so the rule
  is written once, in `RuntimeLibrary`, and nowhere else. The Rust copy the
  language server used (`abi::runtime_library`) is deleted, and the server
  looks for no library of its own: it loads the one `--runtime` names, which
  the VS Code extension passes from its `xmip.runtime.library` setting, and
  says on every validation when none is named. A Rust process cannot call a
  .NET rule, and a .NET surface cannot call a Rust one before the library is
  found; one writing, and the Rust consumer told, is the only way to one.
- **In a composed estate the runtime lies beside every .NET output.**
  `Xmip.Abi`'s project copies the library `cargo build` leaves in
  xmip-core-runtime's `target/debug` into the output of everything that
  references it — the cli, the PowerShell module, the GUI hosts and each test
  project — where the rule's last resort finds it. A deployment puts its own
  there.
- **The script module uses the operator module.** `Xmip/` builds
  `Xmip.PowerShell` into a directory of the session's own on the first command
  that needs it and imports its binary module — never from the project's
  `bin/`, which it would lock, and without the prompt integration
  (`Import-XmipOperatorModule`). `ConvertTo-XmipNodeCapability` calls
  `NodeCapability.Ordered`; `Get-XmipTestResult` reads a snapshot through
  `SnapshotOperator`, which now says the scope it publishes at (`Root()`),
  lists it worst first and names the worst by `ScopeTree.Worst`. Its word
  list, its TOML walk and its mood ranking are gone.
- **The stylesheet paints names, not moods.** An element in a mood carries the
  mood's word and its color's name (`MoodClass`); the sheet renders each name
  to its token as `--mood` and decides no mood's color (ADR-0041's amendment
  of 2026-09-14, corrected the same day).
- **Each rule is tested once, where it is written** — `observe`'s `scope.rs`
  and `health.rs`, `node`'s `stage.rs` — and the runtime's `rule.rs` proves
  each export forwards and has the shape `xmip-core-abi` declares.
  `Xmip.Abi.Tests` proves the crossing, `Xmip.Surface.Test` that the surface
  returns what the export returns, and `test/XmipTest.Test.ps1` and
  `Xmip.Gui.Test`'s `StylesheetTest` that no copy is written again.

## Amendment, 2026-09-24: the last cross-language copies, and a publication read once

The amendment above left seven copies standing, each written in Rust and
again in .NET (open problem 25, "still to do in phase B"), and one set of
presets in the wrong crate. The owner's rule of the same day applies to each
unchanged: one implementation in the crate that owns it, a one-line forwarder
in the runtime's library, one binding in `Xmip.Abi`, and callers.

| Concept | The one implementation | Export | Callers | Copies removed |
|---|---|---|---|---|
| The rollup: a parent is Fine or Holding | `observe::Health::rolled` | `xmip_health_rolled_v1` | `ScopeTree.Rolled`, and through it `Rollup`, `Branches`, `ScopeIndex`, `English.Rollup`, `MoodClass` and every face; `Snapshot::worst` in Rust | `ScopeTree.Rolled`'s own comparison; `Snapshot::worst`'s inline one |
| Counted words and the kind a stage counts | `observe::Counted::word`, `named`, `ALL`, `at` (new `observe/src/counted.rs`, `Counted` moved there) | `xmip_counted_word_v1`, `xmip_stage_counted_v1` | `English.Kind` (the command line's figure names), `ScopeTree.CountedAt` (the board's tiles, the prompt); the Playground and the publication reader in Rust | the Playground's `counted_name`, `counted_named` and `COUNTED`; `SnapshotOperator.ParseCounted`; `ScopeTree.CountedAt`'s table; `MeasureCommand`'s six literal keys |
| Whether a stage pauses, what a thing at it is called | `node::Stage::pausable`, `Stage::location` | `xmip_stage_pausable_v1`, `xmip_stage_location_v1` | `ScopeTree.Pausable` (the Cluster page's pause button), `ScopeTree.Location` (the Configuration page's kind) | `Cluster.razor`'s `IsPausable`; `Configuration.razor`'s three stage cases |
| A node's capability evidence and a run's entry for it | `node::Capability` (`evidence`, `from_evidence`, `entry`, `from_entry`; new `node/src/capability.rs`, moved from the Playground) and where the record sits, `observe::capability` (`scope`, `declared`) | `xmip_capability_published_v1`, `xmip_capability_entry_v1` | `NodeCapability.Declared` (now given the record's scope, and null for any other record), `NodeCapability.Started`, and through them `ScopeIndex`, `RunHeader` and the Configuration page's kind | the Playground's `Capability` and its hand-built `name=a+b` in the roster and the run; `NodeCapability`'s `declares `/`; online;` parse and its `=` split; `ScopeIndex.Declaration`'s and `Configuration.razor`'s test of a leaf called `capability` |
| The topology model and its words (node kind, origin, pattern) | `observe::topology` (`Topology`, `TopologyNode`, `TopologyLink`, `NodeKind`, `Origin`, `Pattern`), moved from the Playground | section 8, as values | the Playground draws with it; every surface reads it through the reader below | the Playground's string-typed model; `SnapshotOperator.ParseNodeKind`, `ParseOrigin`, `ParsePattern` |
| The run header | `observe::Run`, moved from the Playground (which keeps only `run::started`, filling it) | section 8 | `RunHeader.From` | `RunHeader.Read`'s TOML walk |
| A publication's shape: its keys, its words, what an unknown word reads as | `observe::Publication` (`of`, `whole`, `to_toml`, `read`, `snapshot`) | section 8: `xmip_publication_read_v1` and its seven companions (ADR-0027's amendment of the same date) | `SnapshotOperator` through `Xmip.Abi`'s `PublicationReader`, and the Playground's roll, cluster and nodes in Rust | the Playground's `SnapshotReport` and its readers; `SnapshotOperator`'s TOML walk (`Rows`, `Text`, `Number`, `Real`, `ParseState`, `ParseObserved`, the topology parse) |
| The history file (a node's throughput over time) | `observe::Curve` (`of`, `to_toml`, `read`; new `observe/src/curve.rs`) | section 8: `xmip_curve_read_v1`, `xmip_curve_points_v1`, `xmip_curve_free_v1` | `Get-XmipHistory` through the operator module (`PublicationReader.Curve`); the Playground's `history_toml` | the Playground's `HistoryReport`/`PointReport`; `Get-XmipHistory`'s `ConvertFrom-Toml` walk and its `-Counted` word list (now refused against the runtime's words) |
| The activity file (the recent items) | `observe::Recent` (`of`, `to_toml`, `read`; new `observe/src/recent.rs`) and `ItemKind::name`/`named` | none: no surface reads the file yet | the Playground's `activity_toml` | the Playground's `ActivityReport`/`ItemReport` and its own `kind_name` word list |
| The language server's validate entrypoint and its shape | `abi::operate::XMIP_VALIDATE_ENTRYPOINT`, `ValidateFn` (and `StartFn` beside it) | — (a Rust-to-Rust copy) | `xmip-lsp`'s `runtime.rs`; the runtime's `start.rs` proves both exports have the declared shape | `runtime.rs`'s own `ENTRYPOINT` bytes and `ValidateFn` |

- **A publication is read in one place.** `SnapshotOperator` hands the file's
  text to the runtime and builds its index from what comes back; it names no
  key and no word. What a reader does not know it decides once, in
  `observe::Publication`: a mood no one is called is Stressed, so it shows (the
  surface's rule until now); a counted kind no one is called is skipped (the
  Playground's rule until now — the surface counted it as Streams, which
  inflated a figure); a topology word falls back as the surface's did. A count
  crosses at the scope it was recorded at: the surface put every count at the
  publication's own scope, which only a roll's file made true.
- **Where a node publishes its capability is the snapshot's to say.** A
  surface asks whether a record is a node's declaration by giving the runtime
  its scope; it no longer reads meaning from a leaf's name.
- **The topology's parents are Fine or Holding.** ADR-0041 already decided
  it: the Playground draws the cluster, a node, a stage, an endpoint and the
  shared store in the mood of a record at its own scope, else
  `Health::rolled` over the worst beneath it, with that record's evidence; a
  link, which is no parent, keeps the worst leaf at either end. Until
  2026-09-24 a parent carried its worst leaf's own mood.
- **The history file and the activity file each have one writing.** A
  history is `observe::Curve`, read for `Get-XmipHistory` by the runtime; the
  cmdlet walks no TOML and refuses a counted word the runtime does not name.
  The activity file is `observe::Recent`; nothing outside the Playground
  reads it yet, so it has no export — the day a surface reads it, it reads
  through one beside the curve's.
- **Message treatment presets are `message`'s.** `MessageTreatment::CONVERSATION`,
  `BUSINESS` and `PASS_THROUGH` are associated constants beside the type, and
  `Default` is `BUSINESS`; the runtime's `generation.rs` wrote them as three
  functions and is left with the generation itself.

Tested once where each is written — `observe`'s `health.rs`, `counted.rs`,
`capability.rs`, `topology.rs`, `publication.rs`, `curve.rs` and `recent.rs`, `node`'s `stage.rs` and
`capability.rs`, `message`'s `lib.rs` — with the runtime's `rule.rs`,
`rule/node.rs` and `publication.rs` proving each export forwards and has the
declared shape, `Xmip.Abi.Tests` the crossing, and `Xmip.Surface.Test` that
the surface answers what the export answers.

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

The ruling of 2026-09-24 — scope containment keeps two writers, held
together by one shared set of cases, because a surface loads no Rust library
— is the owner's, and he struck it the same day: *Code shall be uniquely
placed, used by others, whom in turn has unique code used by others. It is
common sense.* The amendment that replaces it — one implementation per
concept in its owning crate, forwarded by the runtime's exports and called by
every surface — is the owner's ruling and the lead's design, drafted by the
assistant; the choice of .NET as the one home of runtime discovery, with the
language server told its library, is the assistant's, for the owner to
overrule. ADR-0027's amendment of 2026-09-24 declares the exports, and
ADR-0041's and ADR-0056's amendments point here. The amendment "the last
cross-language copies, and a publication read once" is the assistant's
carrying out of the lead's list of the same day under the same ruling; the
reader's choices for a word nobody knows are the assistant's, for the owner
to overrule; rolling the topology's parents up and giving the history and
activity files one home are the lead's instruction of the same day.

The instruction of 2026-09-24 — the command line and PowerShell share, and
logic goes down the layers — is the owner's; what moved where is the
assistant's drafting of it.
