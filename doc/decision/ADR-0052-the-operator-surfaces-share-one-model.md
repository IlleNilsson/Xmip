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
