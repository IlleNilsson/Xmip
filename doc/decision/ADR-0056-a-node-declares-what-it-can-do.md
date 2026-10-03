# ADR-0056: A node declares what it can do

- Status: Accepted
- Accepted: 2026-09-20, the owner, on being shown what each record named
  as his to strike. Nothing was struck.
- Date: 2026-09-19
- Related: ADR-0022 (identity classes and runtime isolation; the placement
  solver), ADR-0045 (offline is the default), ADR-0050 (an identity
  technology is one mechanism at one gate), ADR-0025 (module loading),
  ADR-0052 (a node carries the roles suitable for its purpose; amendments
  2026-09-24, the surfaces call the node crate's parse, and the node's
  evidence and run entry), ADR-0009 (configuration), ADR-0018 (clause 10a;
  amendment 2026-10-01, executing is the low-latency role), ADR-0015
  (amendment 2026-10-01, a role picks what a build carries), ADR-0027
  (amendment 2026-10-01, the role exports), ADR-0024 (amendment 2026-10-01,
  a Journey claimed through Xmip Storage)

## In brief

- Theme: What Xmip is at runtime
- Subject: What a node says it can do, in the terms work is matched against
- Name: A node declares what it can do
- Order: 13
- Concepts: node capability; node role; online capability; feature capability;
  authentication capability; runtime capability; placement criteria;
  Storage role, Xmip Storage

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
- `runtime-model.md` and open problem 17: a Message in node A's store is
  node A's work, and nothing moves it (answered by the amendment of
  2026-10-01, the Storage role). Placement is the other half of that
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
     ACME, an OCSP responder or a Party endpoint requires it.
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
    declared (`nodes alpha=receive beta=process+send gamma=send`), which is one list
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
  `-Nodes alpha, beta, gamma -NodeCapability @{ alpha = 'receive';
  beta = 'process'; gamma = 'send' }`. This is now the only way a named node carries a stage.
- **Omitting `-Nodes` deals them.** The level's full complement (ADR-0059,
  amendment 2026-09-19) names its own nodes and deals receive, process and
  send round the list by position, which reads no name either.
- **A node given none declares none**, runs the shared-directory tests whole,
  and the roll runs `RoundTrip` itself. That is a real answer and is not
  refused. It is also not what an operator naming three nodes is likely to
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

**2026-09-25: the names themselves go.** Nothing read the letter any more,
but the estate's tests, fixtures and examples still named their nodes that
way, and the owner: *Why does the test code include R1, P1 and S1, those are
parameters to tests!* Every such node in code, tests, fixtures and help is now
named for nothing — alpha, beta, gamma, delta, epsilon, zeta — with what it
does stated in its capability declaration, and `test/NodeName.Test.ps1` fails
the day a node named a stage letter and digits appears where a node's name
stands (a scope, a process name, a declaration, a `-NodeCapability` entry, a
flag naming nodes, or a quoted name). The records keep the names where they
tell what happened.

**2026-09-25, later the same day: the help shows the tester's names.** The
owner names clusters Cn and nodes Rn, Pn and Sn when he runs tests — *That is
why I use Cn, Rn, Pn, Sn. No confusion*; he could not read `north`, which is a
direction — and ruled that help examples and the README show `C1`, `R1`,
`P1`, `S1` as parameter values, with `-NodeCapability @{ R1 = 'receive';
P1 = 'process'; S1 = 'send' }` still saying what each node does and a
sentence saying the names mean nothing to Xmip. Code, tests and fixtures keep
names that carry no meaning; the ruling above stands for them.
`test/NodeName.Test.ps1` allows such a name in a README.md, in the .EXAMPLE
and .PARAMETER sections of a script's help, and in a binary's usage text, and
nowhere else. Provenance: the owner's ruling, 2026-09-25; the placement of
the allowance is the assistant's drafting of it.

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

  **Corrected the same day, 2026-09-24.** The owner: *Code shall be uniquely
  placed, used by others, whom in turn has unique code used by others. It is
  common sense.* Neither keeps a copy. The runtime's library exports the
  words and the parse (`xmip_stage_words_v1`, `xmip_stage_declared_v1`,
  `xmip_operate.h` section 7, forwarding to `node::Stage`);
  `NodeCapability.Ordered` and `ScopeTree.Stages` call them, and the script
  module's `ConvertTo-XmipNodeCapability` calls `NodeCapability.Ordered`
  through the operator module it now loads. `test/XmipTest.Test.ps1` holds
  that no word list is written outside the node crate (ADR-0052, amendment
  "one implementation, and the surfaces call the runtime's exports").

- **The two forms a declaration is said in are the node crate's too**, the
  same day. What a node publishes of itself — `declares receive,send;
  online; …` — and the entry a run lists it by — `edge-01=receive+send` —
  were written by the Playground and read again by `Xmip.Surface`. Both are
  `node::Capability` now (`evidence`, `from_evidence`, `entry`,
  `from_entry`), moved from the Playground, which keeps only the flags it
  starts a node process with; where the record sits, `<node>/capability`, is
  `observe::capability`'s. The surfaces call both through
  `xmip_capability_published_v1` and `xmip_capability_entry_v1` (ADR-0052,
  amendment "the last cross-language copies, and a publication read once").
  A refused published declaration no longer reports the node online: it is
  refused whole (ADR-0055).

Provenance: the case rule is the owner's, 2026-09-24. The rest is the
assistant's drafting of problem 25's row.


## Amendment, 2026-10-01: a node declares its roles, and the stages are theirs

The owner, 2026-10-01, on the node roles: *Thats it and I want to add
Receiving, Processing and Sending. Leave Executing as a sum of Receiving,
Processing and Sending. Executing would be used for Low Latency.* And on the
profiles the same roles now pick a build by: *We can try that and add runtime
role perspective and target node type* (ADR-0015, amendment of the same day).

`NodeRole` had four roles — Operational, Monitoring, Executing, Development —
and the rig declared, beside them and under another name, the stages a node
serves: `--can receive`, `-NodeCapability @{ alpha = 'receive' }`, the
`[run].capabilities` entries, the `declares receive,send` evidence. They were
the same thing: what a node is for on the message path. One thing has one
name, and the name is the role.

- **Seven roles** (`node::NodeRole`, `module/foundation/node/src/role.rs`):
  operational, monitoring, receiving, processing, sending, executing,
  development. Receiving, processing and sending each serve one stage of the
  message path; **executing is their sum** — all three in one process, the
  low-latency choice, a Journey with no process hop (ADR-0018 clause 10a,
  amended the same day). Operational, monitoring and development serve no
  stage. `NodeRole::stages` is the one rule from a role to its stages, and
  `NodeRole::said` the one way a set of roles is said: each once, in the
  order above, and receiving, processing and sending together said as
  executing, so the sum has one spelling.
- **The declaration is the roles.** `NodeRole::declared` is the one parse —
  words by comma or `+`, exact lowercase (the owner's rule of 2026-09-24
  carried over), any other word REFUSED by name (ADR-0055). `node::Capability`
  stays ADR-0056's node capability — the roles and the online capability, the
  record at `<node>/capability` — and reads which stages a node serves from
  its roles alone. `Stage` stays the stage of the message path and the scope
  words, and declares nothing.
- **Deleted, with every use:** `Stage::declared`; `xmip_stage_declared_v1`;
  the Playground's `--can` flag; `Start-XmipTest -NodeCapability` and the
  script module's `ConvertTo-XmipNodeCapability`, `Get-XmipNodeCapability`,
  `Get-XmipNodeCapabilityText`, `Assert-XmipNodeCapability`,
  `Get-XmipNodeCapabilityRefusal` and `Get-XmipNodeCapabilityWarning`;
  `XMIP_PLAYGROUND_NODE_CAPABILITIES`; `[run].capabilities` and
  `XMIP_RUN_CAPABILITIES`; the `capability` key of a Playground node's
  declaration and `Get-XmipTestNode`'s `Capability`.
- **In their place:** `-NodeRole @{ R1 = 'receiving'; P1 = 'processing';
  S1 = 'sending' }` (or `@{ E1 = 'executing' }`), `--role`,
  `XMIP_PLAYGROUND_NODE_ROLES`, `[run].roles` and `XMIP_RUN_ROLES`, the
  declaration's `role` key and `Get-XmipTestNode`'s `Role`, all in role words;
  the evidence reads `declares receiving,sending; online; …`, or `declares no
  role`. `xmip_operate.h` section 7 gains `xmip_role_words_v1`,
  `xmip_role_declared_v1` and `xmip_role_stages_v1`, forwarding
  `NodeRole::WORDS`, `declared` and `stages`; `xmip_capability_published_v1`
  and `xmip_capability_entry_v1` fill roles where they filled stages
  (ADR-0027, amendment of the same day). `Xmip.Surface`'s `NodeCapability`
  carries `Roles`, and `Stages` read through the runtime; `RuntimeRules`
  binds `RoleWords` and `RoleStages`; the script module's
  `Get-XmipNodeRole.ps1` holds the role functions, `Get-XmipNodeRoleWord`
  among them, and keeps no word list.
- **Executing keeps its Journey.** In the Playground a node declaring
  executing hands each pair it received on to itself at process and at send
  (`Roster::target`), so the whole path runs in its one process while the
  other nodes hand on between processes — ADR-0018 clause 10a rehearsed in
  the rig. A running `xmip-service` node says its roles from its
  configuration (`Capability::serving`): receiving where a Receive Location
  starts, processing where a Subscription routes, sending where a Send Port
  starts, executing where all three do.
- **One vocabulary for deployment too.** `deployment-model.md` section 3 named
  three runtime roles — Executor, Reader, Writer — for the same subject. They
  are the node roles now: Executor is receiving, processing, sending or
  executing; Reader is monitoring; Writer is operational; development is the
  Playground's (ADR-0028). The section's rule *do not create a role per
  capability* named receive, process and send hosts among the capabilities it
  kept out of the role model; the owner ruled them in, and the section says
  so. A deployment's roles also pick what its program is built with
  (`deploy/profile/role/<role>.toml`, one per role; ADR-0015, amendment
  2026-10-01).

**Not decided here.** How a node's TOML configuration states its roles —
`xmip-service` derives them from its Locations today — and whether placement
(ADR-0022's solver) matches work against roles or against the stages they
serve. Named so the gaps are on the record.

Provenance: the seven roles, the three new ones and Executing as their sum
for low latency are the owner's, 2026-10-01, quoted above, as is the
direction to consolidate the declaration into the role. The mapping from
Executor, Reader and Writer, the collapsing of the three into executing, and
the Playground's executing node keeping its pairs are the assistant's
drafting of them.

## Amendment, 2026-10-01: the Storage role

**Provenance.** The owner, 2026-10-01, validated part by part with the
assistant, and re-decided later the same day: *to have one or more Xmip Nodes
with role Storage would be a safety… Xmip could just do a round robin over
Xmip Nodes roled Storage*; *The storage node may or may not carry the SQL
storage, it is an IT-infrastructure question… How IT-infrastructure designs
their Database servers is their concern*; and, on a shared database server
IT runs, option A, *Go ahead*. Also *There is nothing local about
either RocksDB or SQLite, they are cluster services running on one or more
nodes*.

- **An eighth role, Storage.** A node declaring it is **Xmip Storage**, the
  doorway to all storage: it serves the storage operations — write a Stream
  chunk, write a Message, claim a Journey, hand it on, write an audit record
  — and every other node calls them, never a database directly. Configuration
  is not among them: each node reads its own TOML into memory (ADR-0031,
  amendment 2026-10-01). It serves no stage of the message path.
- **Round robin, and more than one is the safety.** A node reaches the
  Storage nodes round robin; a Storage node that stops is passed over.
- **What is behind them is IT's.** A database server IT runs on the internal
  network (option A), or, for a single machine or an edge site, the Storage
  node is embedded and keeps RocksDB and SQLite itself, with no failover
  (`deployment-model.md` section 7). A one-node deployment is its own
  Storage node.
- **The executing role is unchanged** (the amendment above): receiving,
  processing and sending in one Host Service, for low latency. Its hand-ons
  still go through the Ledger (`runtime-model.md` section 3).
- **The open question this record named from the Context** — a Message in
  node A's store is node A's work, and nothing moves it — is answered: the
  store is the cluster's, and work moves by a claim through Xmip Storage
  (ADR-0024, amendment of this date). Which node may take the work is still
  this record's placement.

Built 2026-10-01: `node::NodeRole::Storage`, the eighth word, `storage`,
serving no stage; the surfaces read it through `xmip_role_words_v1` as they
read the others, and `deploy/profile/role/storage.toml` is what a Storage
node's program is built with. Xmip Storage itself — its operations, the
embedded Storage node, the wire over Xmip's TLS and the round robin — is
`xmip-core-persist`'s `storage`. How a node's configuration declares the
Storage role, and so when `xmip-service` serves Xmip Storage, is this
record's open question on declaring roles in the TOML, named above.

## Amendment, 2026-10-03: one statement, one Storage node

The round robin is per statement, not per operation (the owner: *When
accessing storage, it should be the same storage node through out a
statement, even if it is repetitive. Writing chunk 1 to n should be regarded
as one statement, one call against StorageN*; the Publication and its
Journeys are the same statement). A receive cycle's chunks, its Publication
and its Journeys are asked of one Storage node, chosen round robin as the
statement begins; one that stops answering mid-statement fails the
statement, never moves it to another, and the sender, never acknowledged,
sends again. So the Publication's one sync covers the chunks before it
whatever is behind the Storage nodes (`runtime-model.md` section 3).

Built 2026-10-03: `xmip-core-persist`'s `storage::statement` and
`XmipStorage::pinned`, which `StorageClient` answers with itself bound to
one node; the runtime's `message_path::carry` takes one statement for the
whole receive cycle.

## Amendment, 2026-10-03: names are parameters and configuration

The amendment of 2026-09-25 misread the owner. *Those are parameters to
tests!* meant that a test takes its cluster and node names as parameters; it
was carried out as a rename, and every node in code, tests, fixtures and help
was given an invented name — alpha, beta, gamma, delta, epsilon, zeta — which
the owner could no more read than `north`. The owner, 2026-10-03: *You
invented alpha and beta some time ago*; *Parameters and configuration is the
way to go, Xmip.toml.*

- **No cluster or node name is written in code or tests.** The invented names
  are struck everywhere outside these records, as the stage letters were.
- **A test's names come from configuration**: the test cluster's `xmip.toml`
  (`test/xmip.toml`, ADR-0031 amendment of this date), or the one a run names
  — `Start-XmipTest` passes `-Cluster` and `-Nodes` and the cluster file it
  writes. One fixture per language reads it; a test finds a node by what it
  declares or by position, never by a literal name.
- **Where a name may stand**: in an `xmip.toml`, in a README, in the help
  examples of a command, and in a binary's usage text — C1, R1, P1, S1 as the
  owner types them. `test/NodeName.Test.ps1` refuses any other.

Built 2026-10-03: one fixture per language — `configure::fixture`
(`test_cluster`, `other_cluster`), .NET's `TestCluster` (`Read`,
`ReadOther`) and PowerShell's `Get-XmipTestCluster` — reading
`test/xmip.toml` and the second test cluster's `test/other/xmip.toml`, each
node's roles through `configure::cluster::roles`; every literal cluster and
node name in code and tests moved onto them, and the snapshot fixtures a
.NET test holds to a test cluster are allowed by `test/NodeName.Test.ps1`'s
`$script:Held`, which also catches the `Nn` shape. A Playground roll's nodes
are its cluster file's `[nodes]` (`Roster::of_cluster`), named by
`XMIP_TEST_CLUSTER`: `Start-XmipTest -Cluster -Nodes -NodeRole` writes the
run's own (`Write-XmipTestCluster`), and an omitted `-Nodes` takes the test
cluster's as it is. The node count is deleted — `-Nodes <count>`,
`XMIP_PLAYGROUND_NODES`, `XMIP_PLAYGROUND_NODE_NAMES`,
`XMIP_PLAYGROUND_NODE_ROLES`, `roll --roster <level>`,
`Get-XmipNodeComplement`, `complement.rs` and `Stress::nodes`.
