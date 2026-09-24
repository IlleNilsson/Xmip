# ADR-0056: A node declares what it can do

- Status: Accepted
- Accepted: 2026-09-20, the owner, on being shown what each record named
  as his to strike. Nothing was struck.
- Date: 2026-09-19
- Related: ADR-0022 (identity classes and runtime isolation; the placement
  solver), ADR-0045 (offline is the default), ADR-0050 (an identity
  technology is one mechanism at one gate), ADR-0025 (module loading),
  ADR-0052 (a node carries the roles suitable for its purpose), ADR-0009
  (configuration)

## In brief

- Theme: What Xmip is at runtime
- Subject: What a node says it can do, in the terms work is matched against
- Name: A node declares what it can do
- Order: 13
- Concepts: node capability; online capability; feature capability;
  authentication capability; runtime capability; placement criteria

**A node declares its capabilities, and work is placed on a node whose
capabilities satisfy what the work requires. There are four kinds: online,
feature, authentication and runtime. They are the criteria placement works
with, and a requirement no node satisfies is refused with both sides
named, never placed somewhere that cannot serve it.**

## Context

The owner, 2026-09-19, having just ruled that a node carries the roles
suitable for its purpose: *a node may have online capability, some feature
capability, authentication or runtime capability. Those are criterias to
work with.*

The estate had anticipated this and never said what a capability is.

- ADR-0022's consequences: *Placement becomes a solver. The runtime must
  satisfy node capability, identity context separation and configuration
  requirements together. Today's placement is simpler than that, and this
  is the clause that will force it to grow.*
- `deployment-model.md`: *Any capable node may resume work if it can
  satisfy the required capabilities* — and, further down, that a profile
  says *which cluster capabilities exist*.
- `runtime-model.md` and open problem 17: a Message in node A's ToDo is
  node A's work, and nothing moves it. Placement is the other half of that
  question — before work can reach another node, something must say which
  node is fit to take it.

Three records point at a thing none of them defines. This one defines it.

## Decision

1. **A node declares its capabilities; nothing is inferred.** A node's
   capabilities come from its configuration and from the Modules it
   loaded (ADR-0025), and it publishes them the way it publishes health.
   No capability is guessed from a socket, a probe or a successful call,
   for the same reason ADR-0052 draws only what is configured or observed
   and infers nothing between them.

2. **Four kinds, and they are the criteria.**
   - **Online capability** — whether a route off this machine may be
     assumed. ADR-0045 makes offline the default, so this is the one
     capability whose absence is the normal case. Work that must reach
     ACME, an OCSP responder or a partner endpoint requires it.
   - **Feature capability** — what the node can actually do with a
     Stream: the transports, contracts, paths, archives and logic its
     Modules registered. A Journey that decodes EDIFACT requires a node
     that has the EDIFACT contract.
   - **Authentication capability** — which mechanisms the node can verify,
     in ADR-0050's terms: one mechanism at one gate. A Receive Location
     that accepts Kerberos requires a node holding the keytab; one that
     accepts mutual TLS requires a node holding the chain. This is the
     capability most often missing in a cluster that looks uniform.
   - **Runtime capability** — what the node can host: the runtime library
     it loaded, the identity contexts it may isolate (ADR-0022), the
     resources it was given. A node that cannot open an eighth host
     process cannot serve an eighth identity context.

3. **Work states requirements in the same four terms.** A requirement is
   written where the work is configured, not deduced at placement time,
   so an operator can read what a Journey needs without running it.

4. **Placement is a match, and a failed match is refused.** Placement
   chooses among the nodes that satisfy every requirement. Where none
   does, the estate refuses and names both sides: the requirement that
   went unmet and the nodes that were considered (ADR-0055; ADR-0022
   already rules that a failure naming neither sends someone reading
   configuration files for an afternoon).

5. **Capability is not permission.** A node that can verify Kerberos is
   not thereby allowed the work; Acceptance and the authorization gate
   still decide. Capability answers *could this node serve it*, never
   *may it*.

## Consequences

- ADR-0022's solver clause has its input defined. The solver still has to
  be built; what it reads is now on the record.
- Open problem 17 keeps its question — how work *moves* — and loses the
  prior one: which node could take it is answerable before any protocol
  exists to carry it there.
- **The Playground models two of the four, and says which two.** Online
  capability was already there — `-OnlineNodes`, the `--online` flag and
  the `switch` record, published per node since ADR-0045 — and feature
  capability landed with this record, as the stages of the message path a
  node can serve: `--can receive`, `--can process,send`, one or more per
  node. Both live in one value (`test/playground/src/capability.rs`), so
  the rig has one notion of what a node can do and not two. A node is
  started with its capability, publishes it at
  `xmip:///<cluster>/node/<name>/capability`, and the topology takes a
  node's stages from that record; `[run]` says what each node was started
  with. **Authentication and runtime capability are not modelled**: the
  Playground verifies no credential and isolates no identity context, so
  either would be a word with nothing behind it. The node's own capability
  record says so in as many words, rather than leaving a reader to guess
  which of the four a silent rig means.
- The rig had briefly done the opposite — a node's stage read out of the
  first letter of its name — and the owner refused it the same day: *I
  know, so why do you break it!* A name is not a criterion. One place kept
  a letter for a day — `Start-XmipTest -Nodes R1, P1, S1` expanded it into a
  capability at the operator's door — and the owner struck that too on
  2026-09-20 (amendment below): `-NodeCapability` states it outright, and
  nothing anywhere reads a node's name.
- A profile's *cluster capabilities* in `deployment-model.md` should be
  read as the union of its nodes' capabilities; that document's wording was
  reconciled with the four kinds on 2026-09-20 and now says so.
- **2026-09-19, the surfaces: all four show it, and none parses the file.**
  ADR-0014's amendment of the same day — *a change reaches every surface, or
  says which it did not* — was owed for this record, whose capabilities
  reached the snapshot and stopped there. The model went into
  `Xmip.Surface` first: `NodeCapability` is what one node declares, read
  either from the record the node published at `<node>/capability` or from
  `[run].capabilities`, which `RunHeader` no longer ignores.
  `ScopeIndex.Capability(node)` answers from the published record in the one
  pass the index already makes, and a surface prefers it over `[run]`,
  because clause 1 says a node declares its own capabilities and `[run]` says
  only what it was *started* with; `NodeCapability.Origin` says which of the
  two a reader is looking at. The three faces render that and parse nothing.
  - **GUI** — the run line on every view names each node with what it
    declared (`nodes R1=receive P1=process+send S1=send`), which is one list
    where two would have crowded it; the topology's inspector says a node's
    capability when the operator has drilled to that node, with the
    publisher's whole sentence on the row; the configuration tree carries
    the capability as a row of its own beneath the node, named `capability`
    rather than filed under *technology*.
  - **CLI** — owed nothing for the capability itself and was shown to owe
    nothing by running it: a capability is a scope, so `xmip-cli list
    <node>` already listed it and `xmip-cli show <node>/capability` already
    printed the node's own words. What it did owe was the run, which it had
    never shown at all: `xmip-cli health` now prints the same line the GUI
    does, and `--json` carries it as `run`.
  - **PowerShell** — `Get-XmipTestNode` carries `Capability` beside
    `Online`, read from the `--can` flag the cluster starts each node with.
    A parameter on a known noun, not a cmdlet.
  - **What still owes nothing.** Authentication and runtime capability reach
    no surface because nothing publishes them; the rig says so in its own
    evidence rather than being silent. The prompt segment is unchanged.

- **Not decided here.** How a capability is written in configuration, how
  a requirement is written beside a Journey or a Receive Location, and
  whether the four kinds are a closed set. Named so the gaps are on the
  record rather than in someone's memory.

## Alternatives considered

**Infer capability from what a node has done.** It is cheap and it is a
guess: a node that has never verified Kerberos may be perfectly able to,
and a node that did so last week may have lost its keytab since. The
estate does not infer between configured and observed.

**One flat list of capability strings.** Simpler to match, and it loses
the question each kind answers. An operator diagnosing a refusal wants to
know whether the node lacked a contract, a credential, a route or room to
host — four different mornings' work.

**Leave it to configuration alone.** Configuration says what a node *is
to do*; capability says what it *could do*. A cluster where every node is
configured identically has no placement problem and also no reason for
more than one node.

## Provenance

The four kinds are the owner's, 2026-09-19, quoted in the Context. The
five clauses, the consequences and the reconciliation with ADR-0022 and
problem 17 are the assistant's drafting of them, and the record is
Proposed rather than Accepted until the owner says so.

## Amendment, 2026-09-20: the last letter that meant something is gone

The owner: *Rn, Pn and Sn are arbitrary node names.* He had said the same of
clusters an hour earlier: *C1 and C2 are not roles, they are arbitrary cluster
names, there may be one or more clusters.*

The Consequences above record one surviving exception to clause 1 — that
`Start-XmipTest -Nodes R1, P1, S1` read the first letter as a capability at
the operator's door, and that nothing downstream did. That exception is
struck. `Get-XmipNodeCapability` returns what `-NodeCapability` states for a
node and nothing otherwise; no letter of any name means anything anywhere in
Xmip.

What an operator gets instead, and how it is said:

- **`-NodeCapability` states it**, one entry per node:
  `-Nodes R1, P1, S1 -NodeCapability @{ R1 = 'receive'; P1 = 'process';
  S1 = 'send' }`. This is now the only way a named node carries a stage.
- **Omitting `-Nodes` deals them.** The level's full complement (ADR-0059,
  amendment 2026-09-19) names its own nodes and deals receive, process and
  send round the list by position, which reads no name either.
- **A node given none declares none**, runs the shared-directory tests whole,
  and the roll runs `RoundTrip` itself. That is a real answer and is not
  refused. It is also not what an operator typing `R1, P1, S1` is likely to
  have meant, so `Start-XmipTest` **says so in words before anything spawns**
  (ADR-0055 clause 5), naming `-NodeCapability` and the complement as the two
  ways to split the message path.
- **The `RoundTrip` refusal** — a roster that declares some stages but not all
  three — now ends by naming both of those ways rather than only the
  capability nobody declared. With the shorthand gone it is the signpost an
  operator meets most often.

The compromise this strikes was the assistant's, made on 2026-09-19 and
flagged at the time as the one place a name still carried meaning. It carried
for a day.

## Amendment, 2026-09-24: the node crate reads the words, lowercase exactly

Open problem 25, row i: a declared capability was read three ways. The
Playground and PowerShell refused an unknown word and ignored case;
`Xmip.Surface` dropped an unknown word without a word and matched case
exactly. The decision above is unchanged; how and where the words are read
is now one rule.

- **The words are exact lowercase only.** The owner, 2026-09-24: `receive`,
  `process` and `send` are the words, and `RECEIVE` or `Send` is an unknown
  word, refused with the same sentence as any other. No record had ruled on
  case before; this is his ruling, not a reconciliation of the copies.
- **`node::Stage` is the stage, and `Stage::declared` the one parse**
  (`module/foundation/node/src/stage.rs`). Words are separated by commas or
  `+`, blanks ignored, returned in path order, and any word that is not one
  of the three is REFUSED, naming every such word and the words there are
  (ADR-0055).
- **The Playground reads through it**: `--can`, `--nodes` and a published
  capability record alike. Its own `Stage` copy is gone; every verdict, hop
  and scope uses the node's.
- **PowerShell and `Xmip.Surface` keep a copy**, because neither reaches
  Rust for this: the script module calls no native library, and a surface
  reads a snapshot with no runtime loaded while `xmip_operate.h` carries no
  such call. Both copies follow the same rule, and a refused declaration
  reaches the surfaces as its refusal (`NodeCapability.Refusal`, said by
  `Line()`). `test/XmipTest.Test.ps1` holds the three word lists and the
  refusal sentence equal.

Provenance: the case rule is the owner's, 2026-09-24. The rest is the
assistant's drafting of problem 25's row.
