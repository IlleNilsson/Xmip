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

## Amendment, 2026-09-18: the executable is `xmip-cli`

ADR-0053: every System Process Xmip owns is named `xmip-<what>`, the
executable included, so that one line finds and stops them all. Where this
record says the `xmip` executable, read `xmip-cli`; an operator types
`xmip-cli health <scope>`. Nothing else about it changes.

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
