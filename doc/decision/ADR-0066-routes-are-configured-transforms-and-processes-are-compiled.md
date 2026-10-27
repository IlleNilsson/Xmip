# ADR-0066: Routes are configured and compiled at start; transforms and processes are compiled at design time

- Status: Accepted
- Accepted: 2026-09-26, the owner, in the words quoted below
- Date: 2026-09-26
- Related: ADR-0031 (configuration is TOML; amendment 2026-09-26, never a
  database), ADR-0046 (route technologies and filters), ADR-0012 (the module
  boundary), ADR-0064 (developers design in VS Code; Xmip Application),
  `.ai-interaction`'s filter and expression research of 2026-09-26

## In brief

- Theme: What Xmip is at runtime
- Subject: When each kind of design becomes something that runs, and the one
  expression language they share
- Name: Routes are configured; transforms and processes are compiled
- Order: 16
- Concepts: expression; compiled at start; compiled at design time; compiled unit

**A route is configuration: its filter is text in the Xmip Application's
TOML, compiled once when a node starts and evaluated from the compiled form.
A transform and an Xmip Process are code: what a developer
designs is compiled at design time into an artifact a node loads, so a
mistake in one is found when it is built, not when a Message arrives. Both
use one expression language, Xmip's own and deliberately small, owned by one
crate.**

## Context

The owner asked for designers like BizTalk's (ADR-0064) and, asked how a
filter should be written, called it *just code* and asked for research. Two
studies followed the same day: how products store a filter, and nineteen
expression languages compared. They found Xmip holding three grammars for
one job (`route::Predicate`, the `expression:` technology, `path/predicate`),
one of which parsed its expression again on every evaluation.

Asked whether every expression must be showable in a designer, the owner
answered with the rule that decides the rest: *Maps, transformations,
processes have to be compiled during design time. Routes are configurable
items, compiled at runtime startup. If you do not have a better idea.*

## Decision

### 1. Two moments of compilation

- **Routes** are configuration (ADR-0031): a Subscription's filter is text
  in the Application's TOML, read by `configure`, compiled when the node
  starts, and refused then — not at the first Message — if it names what no
  loaded technology provides or compares a value to the wrong kind.
- **Transforms and Xmip Processes** are code: the designer's
  document is compiled at design time into an artifact a node loads through
  the module boundary; the node never interprets a design.

Built 2026-09-26, for routes. A Subscription's `filter` is the compiled
`path::expression::Expression`, read from its text as `configure` reads the
Application, so an Application whose filter does not parse, or compares a
value with the wrong kind (`Amount > 'x' + 1`, `1 = 'x'`), is refused by
`application_problems`, by `xmip_validate_v1` for every surface, and by the
runtime as the node starts (`start.rs`,
`a_filter_that_does_not_compile_refuses_the_node_at_start`). A name no
loaded technology reads is still refused at arrival, before any Journey
opens, as the owner confirmed in ADR-0046 the same day: the runtime holds no
set of loaded route technologies at start yet (the `Runtime`'s
`gathering` is compiled only where a `Runtime` is built; ADR-0046, amended
2026-09-27), so that half
of this clause waits for the runtime to load route technologies as modules
(ADR-0018 phases 4 to 9). Transforms and Xmip Processes: not built.

### 2. One expression language, Xmip's own

One small language, SQL-WHERE-shaped, owned by one crate: bare names with
their prefixes (`header:http.x-channel`), text in single quotes, `and`, `or`,
`not`, comparisons, `in`, `like`, `||`, `coalesce` and arithmetic; no loops,
no functions of the user's own, no I/O; its cost grows only with its length.
A missing value is *unknown*, carrying the reason route gives today, never a
silent false. It replaces `route::Predicate`, the `expression:` technology
and `path/predicate`'s grammar; a subscriber's filter in the Event wire
form's own language (ADR-0065) is read into the same tree.

Built 2026-09-26. **The crate is `xmip-core-path`**, the path capability
itself — its `expression` module; no new repository. Chosen by who must
depend on whom: route's filters use it now, `configure` reads its tree for
the designer's rows, and a transform and an Xmip Process will generate Rust
that builds and evaluates the same tree, so the tree lives below all of
them. Not in route: a transform depending on route for its expressions
would depend on the wrong capability. Not in `path/predicate`, where the
grammar was: that is a technology, and `configure` is a platform service,
which `architecture.toml`'s policy lets depend on a capability and never on
a technology. Path is what route (its `content` technology) and transform
already build on, and its parser cursor is shared with FHIRPath
(ADR-0044); FHIRPath stays its own language. `xmip-core-path-predicate`,
whose one caller was the retired `expression` technology, is undeclared
and unmounted; its GitHub repository is untouched.

- **The grammar.** Names bare with their prefixes, a run of `.`, `:`, `/`
  or `-` joining two word characters, so `header:http.x-channel` is one
  name — which is why subtraction and division are written with space
  around them — or in double quotes, a quote doubled
  (`"regex:OrderNo:^INV-(\d+)$"`). Text in single quotes, a quote doubled
  (`'O''Brien'`); integers (64-bit) and `true` and `false`; **no decimals**,
  route's rule since ADR-0046 (a decimal literal is refused with that
  reason). `=`, `<>`, `<`, `<=`, `>`, `>=`; `[not] like` with `%` and `_`
  and no escape; `[not] in (…)`; `exists X`, with `X is not null` read as
  it and `X is null` as `not exists X`; `and`, `or`, `not`, parentheses;
  `||`, `+ - * /` (integer division), a unary minus, `coalesce(…)`.
  Precedence is SQL's: `or`, `and`, `not`, one comparison, then `||`,
  `+ -`, `* /`, unary minus. Keywords in any case. A value where a condition
  belongs is refused (`Urgent` alone: write `Urgent = true`), so every
  condition is a row.
- **`!=` is read as `<>`, and `==` is refused.** SQL's spelling is `<>`
  and the canonical text writes it; `!=` is accepted because Service Bus
  SQL and the Event wire form's filter language accept both and the retired
  predicate language and the designer's rows used it, so refusing it would
  break a habit for no gain in meaning. `==` is no spelling SQL or that
  filter language has; it is refused with
  "equality is '='", so the language keeps one equality.
- **Kinds are checked once.** A literal's kind is its spelling; a name has
  none and takes the kind of what it meets (`Amount > 1000` reads Amount as
  an integer). Parts whose kinds cannot meet are refused when the text is
  compiled, never at a Message.
- **Unknown.** A name with no value, text that will not read as the kind
  asked, a division by zero or an overflow is *unknown*, carrying route's
  reason (`nothing promoted Region`), in SQL's three truths; `coalesce`
  takes the first part that is known. Only *true* matches.
- **Parsed once.** `Expression::parse` parses and checks; `evaluate` walks
  the tree and never parses (the old `PredicateEngine::read` parsed on every
  read; that engine is retired with its repository). Measured on this
  machine, release build: the research filter (77 characters) compiles in
  5.6 µs and decides in 1.8 µs on a quiet machine, and in up to 97 µs and
  4 µs while other builds loaded every core; a filter of 154 characters
  with `in`, arithmetic, `like`, `coalesce` and `exists` compiles in 11 µs
  and decides in 0.9 µs quiet, up to 158 µs and 24 µs loaded. Every figure
  is far under the millisecond rule, and the compile happens once per
  Subscription, at load. A reason is written only where it is
  kept: under `not`, and inside an `or` that holds, none is.
- **One canonical spelling.** The tree prints as the text a designer
  writes: keywords lower case, one space around operators, `<>`, `exists`,
  parentheses only where precedence needs them and around a group inside a
  group, so a group drawn inside a group prints back as one. Canonical text
  parses to a tree that prints as the same bytes; any accepted text prints
  as its canonical equivalent. An `Expression` keeps the text it was read
  from and writes it back unchanged: reading never reformats.
- **Replaced.** `route::Predicate`, `route::Value` and `route::Test` are
  gone and `route::publish` decides the compiled tree; the `expression:`
  technology is retired (ADR-0046, amendment 2026-09-26); the predicate
  engine's two-quote grammar and its null-is-false evaluator are gone.
- **The Event wire form's filter language is not read yet.** ADR-0065's
  events filter by scope and outcome and carry no such filter today, so
  nothing needs it; reading one into this tree waits for the first
  subscriber that sends one.

### 3. What the designer shows

Every filter has rows: the language is kept to what rows can hold. A transform's
values and an Xmip Process's decisions are edited in their own designers;
a Decide is a decision table (DMN's shape, not its grammar), and anything a
builder cannot draw opens the text.

Built 2026-09-26, for filters. `configure::filter` is the filter dialog
over the compiled tree: a comparison, `like`, `in` or `exists` is a row of
property (the left side, in the language), operator (the language's
`OPERATORS`) and value, with a kind — `text`, `integer`, `boolean`, or
`expression` for a value written in the language itself, such as another
name or the list an `in` holds; `and` and `or` are groups and `not` wraps
any part. Rows become the tree and its canonical line only when the
designer edits (`set-filter`); a hand-written line is left as written.
Tested both ways (`filter.rs`): fourteen canonical filters go text → rows →
text byte for byte, and seven non-canonical ones go to their canonical
equivalent, compiling to the same tree. The VS Code designer draws the rows
and shows the one line under "As text", both through `xmip-lsp` and the
runtime's section 10 exports; the operators and kinds it offers are the
server's.

### 4. Compiled to a native module, through Xmip's own ABI

The owner, 2026-09-26, from two (a native module in Rust, or WebAssembly):
**a native module.** A transform or an Xmip Process is generated as Rust and
compiled into a library a node loads through the C ABI, as every other
module is (ADR-0012) — memory-safe, at native speed, built once per target
platform as Xmip itself is, and needing no WebAssembly runtime in a node.

## Consequences

- The three grammars become one; the parse happens once, at start or at
  build, never per evaluation.
- The filter in the Application file becomes one readable line; the
  designer's rows are a view of it (ADR-0064 clause 4).
- A transform and an Xmip Process need a compile step in the developer's tooling
  — generate Rust, build the library, check it against the module boundary —
  and the developer's machine needs the Rust toolchain the estate already
  declares.

## Provenance

**The owner's**, 2026-09-26: clause 1, in the words quoted in Context, and
clause 4, chosen from the two named there.

**The assistant's**: clause 2's language, drawn from the two studies, and
clause 3; the owner accepted clause 1 as the frame with *if you do not have a
better idea*, and each of 2 and 3 is his to strike.

## Amendment, 2026-09-28: clause 1's other half

A running node compiles its Subscriptions' filters once, through the route
technologies its program linked, and refuses to start while a filter names
what none of them reads (`xmip-core-runtime`'s `startup.rs`,
`what_the_program_was_not_built_with_refuses_the_node_at_start`), as clause
1 decides. The route gathering is built once, with the node's `Runtime`.

## Amendment, 2026-10-22: Prepare, Promote, Demote, Transformation and a Work Process's flow are calls to compiled units

The owner, 2026-10-22, on Prepare, Promote, Demote, Transformation and a
Work Process's flow: *They are tricky but not impossible. They are compiled units. They
just have to be referred to in the VS Code extension, ending up in the TOML
configuration.* Compiling them stays clause 4's; what the configuration
holds is the reference. Decided by the owner the same day, in the keys
drafted for him: a unit is a function a Module provides, and a step entry
is a call to it with arguments.

- **A Module declares its units** in its manifest, `[[modules.manifest.units]]`
  (`abi::ModuleUnit`): `name`; `capability`, what it can be called as —
  `prepare`, `promote`, `demote`, `transform`, `work-process` or `validate`
  (*Validation according to format or custom contracts has to be in
  there*), never read from its name; `stages`, the stages it serves; and
  `settings`, what a call may give, in the shape a technology declares a
  Location's settings in, each with its kind, default or requirement, words
  and meaning (`abi::UnitSetting`, xmip-core's `Setting` as data).
- **Stages.** The owner: *So there has to be a need for a separation of
  prepeare units. Like receive, process and send*, and then: *Maybe we
  should use the terms Receive, Process and Send Preparation more clear. The
  code used in a prepare situation is usually similar. It is just an enum
  away what it does in what situation.* A unit lists the stages it serves,
  `stages = ["receive", "process", "send"]` or fewer, in the message path's
  own stage words, read by `xmip-core-node`'s `Stage` and never listed again;
  called, it is handed the stage it is called at, so one unit may compress
  on send and decompress on receive. Promote serves receive alone and Demote
  send alone, by definition; a Work Process's flow, a Debatch, may serve
  receive as well as process. A prepare unit at each stage is a Receive
  Preparation, a Process Preparation or a Send Preparation; *A transformation is not a prepare, just so
  we are clear*: the other kinds have stages and are never called
  Preparation.
- **Offline, explicitly.** The owner: *We can only use standards, code and
  compiled units that explicitly work offline! The offline units may be
  updated, but on the end user's request, after a review.* A manifest says
  `offline = true` for the module and for each unit, and configure refuses
  one that does not, in words, at validation and as a node starts. The
  module's version, `[modules.manifest.identity] version`, is what the
  configuration pins; a module is never updated by itself (the update act is
  ADR-0045's, amendment of this date).
- **A call is an entry** of one of four lists, in a node's document — the
  cluster's top or `[nodes.<name>]` — and in an Xmip Application's section:
  `[[preparation_steps]]`, `[[promotions]]`, `[[demotions]]` and
  `[[transformations]]`, each with `name`, `module` (a `[[modules]]` entry),
  `unit` (one of that module's units, of the list's capability) and
  `settings`, held to the unit's declaration as a Location's settings are to
  its technology's. A Work Process names its flow by `module`, `unit` and
  `settings` the same way, a `work-process` unit serving `process`.
- **Attachment**, on the four artifacts, by the entry's name, as ADR-0031's
  amendment of 2026-10-05 places them: `prepare = [...]` in order,
  `transform`, `promote` on a Receive Port or Location alone, `demote` on a
  Send Port or Location alone. Receive runs the Location's, then the
  Port's; send the Port's, then the Location's. An artifact attaches entries
  of its own document's lists: a node's Locations and bound Locations the
  node's, an Application's Ports and Locations the Application's.
- **Refused**, in words, by `xmip_validate_v1` for every surface and as a
  node starts (`configure::step::problems`): a module no `[[modules]]` entry
  declares, a unit its manifest does not declare or declares as another
  capability, a stage word that is none, a unit listing a stage twice or
  none, a Promote or Demote unit listing another stage, a call's settings
  its unit's declaration refuses, an attachment naming no entry, a unit
  attached at a stage it does not serve, and a Promotion on send or a
  Demotion on receive.
- **Assignment is not configured.** The owner: *Assignments are not
  configured, they are done by primarily Work Processes.* No key names one;
  a Work Process's compiled code assigns through the assign capability.
  And: *Transformation and Assignment where ever they occur, creates a new
  message from a previous or created message* (terminology).

Built 2026-10-22, the reference, not the running: `abi::unit`,
`configure::step`, `configure::modules`, the Module, Prepare, Promote,
Demote and Transformation views of the designer and the Operation Desktop
(ADR-0064, amendment of this date). Running a unit is decided, not built: a
node refuses to start a Port or Location that attaches one, saying this
runtime runs no compiled unit yet (`configure::step::unrun`, startup phase
3). The standard units are separate work (`xmip-core-unit`).

## Amendment, 2026-10-22: a Work Process is designed in BPMN 2.0, compiled to a unit and run from the Ledger

The owner, 2026-10-22: *I would like a Work Process to be designed in VS
Code, but at the end of the day it is a compiled piece executed when called
upon. … there are BPEL solutions out there, no need to invent the wheel
unless we have to*; then *go with the best functionality agreeing with Xmip
licensing*, and *Go for it*. Of the choice made, BPMN 2.0: *It can not be
the only choice, just the default one.* Clause 1's other half for Work
Processes and clause 4 are built by this amendment.

### 1. A design format is a technology behind one trait; BPMN 2.0 is the default

- **One trait, one compiled form.** `xmip-core-process`'s `DesignFormat`
  reads a design and compiles it to the one `Program`; a design names its
  format, and `bpmn` is assumed where it names none (`DEFAULT_FORMAT`). The
  engine runs a `Program` and never learns which format it came from.
- **BPMN 2.0 is the default technology**, `xmip-core-process-bpmn`, mounted
  beside the capability's source. OMG's specification licenses anyone to
  build software on it, which agrees with Xmip's AGPL; its XML with BPMN DI
  is what every BPMN tool opens, so a design drawn in Xmip's own VS Code
  designer is a standard `.bpmn` file and one drawn elsewhere compiles here.
  The designer is Xmip's own TypeScript and SVG; bpmn-js is not used (it is
  JavaScript, and its license demands a visible watermark).
- **Other formats come later as technologies of their own**, behind the
  same trait: WS-BPEL 2.0, or the Open Workflow Specification — the latter
  only where a technology for it can be built that explicitly works
  offline: its catalogs, `use` resources and endpoints may name remote
  documents, and any technology for it must resolve locally only and refuse
  a remote reference at design and compile time. A unit written by hand is
  already a format of its own: it implements `process::Flow`.

### 2. Offline, always

The owner, 2026-10-22: *We can't be dependent on resources online, check
that out!*, and *We can only use standards, code and compiled units that
explicitly work offline! The offline units may be updated, but on the end
user's request, after a review.*

- The BPMN 2.0, BPMN DI, DC and DI XML Schemas of OMG's BPMN 2.0.2
  publication ship inside the technology, unmodified (`schema/`). A
  namespace is a name and is never fetched; a `schemaLocation` for a
  namespace Xmip ships a schema of is answered by that schema, its location
  never read.
- Any other location, in a `schemaLocation` or a `bpmn:import`, that names
  a network resource is refused in words before anything is asked
  (`process::remote`); a local one is read through `LocalResources`, files
  beside the design. A BPMN document imported for its definitions is refused
  in this version: one design is one document. Proved with no network
  attempt (`a_remote_import_is_refused_in_words_and_nothing_is_asked_for_it`).
- A document type declaration is refused, so no entity of anyone else's is
  expanded. Neither the compiler nor the engine opens a connection.
- A compiled unit's manifest says `offline = true`.
- **The XML reader is quick-xml** (0.42, MIT, no default features; its one
  dependency is memchr, MIT or Unlicense). Neither holds network code: their
  sources were searched for `std::net`, sockets and HTTP clients on
  2026-10-22 and hold none. Validating a design against the shipped schemas
  waits for `xmip-core-contract-xml-schema` to read `import` and `include`,
  which it refuses today.

### 3. What BPMN 2.0 compiles to, in this version

The owner, 2026-10-22: *Correlation is a big thing, process things in
order. Compensation can mostly be handled with try/catch. Rules can be
handled in code. Human tasks, waiting for an email, text or a phone call can
wait.*

| BPMN 2.0 | The Work Process program |
| --- | --- |
| process (`isExecutable`), none and message start events | the Instance's start |
| `serviceTask` with `xmip:call module unit` | a call to a compiled unit; a rule is code |
| `serviceTask` with `xmip:debatch` | the split, each part published back through routing |
| `task` with `dataOutputAssociation` and `assignment` | an Assignment: a new Message generation |
| `sendTask`, message throw and end events | the current Message published back through routing |
| `receiveTask`, message catch events | a wait for the next Message of the Instance's key |
| `receiveTask` with `xmip:batch most within` | a Batch: Messages of the key made one, their Sections in order |
| timer catch events (`timeDuration`, `timeDate`) | a due time in the Ledger |
| exclusive gateway, `conditionExpression` in `urn:xmip:expression`, default flow | a decision in Xmip's expression language |
| parallel gateway | a fork and a join |
| embedded `subProcess` | a scope, laid flat |
| interrupting timer boundary event | a scope's timer |
| interrupting error boundary event, error end event | try and catch: a scope catching a code |

Refused in words, naming the element: compensation, transactions and cancel
events (*handled with try/catch*); user and manual tasks (*can wait*, open
problem 50); business-rule tasks (*Rules can be handled in code*); script
tasks (a node never interprets); call activities, inclusive, complex and
event-based gateways, signal, escalation, conditional and link events,
event subprocesses, loops and multi-instance, ad hoc subprocesses,
choreographies, and any element the compiler does not read. A failed unit
call throws the code its unit answers; an exclusive gateway whose
conditions all fail with no default throws `no-branch`; a flow that never
waits throws `loops`.

### 4. Compiled to a unit, loaded through the C ABI, run a turn at a time

- **The compiled form is `process::Program`**, a graph of typed steps with
  every flow resolved and every subprocess laid flat, kept in its binary
  form (`process::form`). `process::generate` writes the Work Process unit
  it is built into: a Rust crate carrying the program's bytes, exporting it
  with `process::export_work_process!`, built as a `cdylib`, and the
  `[[modules]]` entry declaring it (`capability = "work-process"`,
  `[[modules.manifest.units]]` with `stages = ["process"]` and
  `offline = true`).
- **Loaded through the module boundary.** A Work Process compiled from a
  user's design ships apart from Xmip, so it is a library a node loads and
  never linked into the service, and a change to a process never rebuilds
  the node: `xmip_module.h` section 13, the work process table —
  `declared`, what the unit declares, and `advance`, one turn: the
  Instance, the event and the time in, the Instance and the acts out —
  opened by `runtime::ffi::loaded_work_process` as a `process::Flow`. A
  `[[work_processes]]` entry names its flow by `module` and `unit`.
- **The engine is `process::flow`**: a turn takes the Instance as the
  Ledger holds it and one event — a Message of its key arrived, work done
  or thrown, its time due — and answers the acts the runtime carries out:
  work on a Message, Messages made one, a Message published, how it ended.
- **The runtime's Work Process step** (`runtime::work_step`) claims a
  Journey bound for a Work Process, finds its Instance through the
  Correlation table, advances it, carries out its acts, and hands it all on
  in one write (`XmipStorage::turn`): the Journey, the new Messages, the
  Journeys published, the Instance, its correlation keys, and — where a
  timer waits — the Journey kept at its place with a due time. **Nothing
  waits on a thread**: an Instance waiting for a Message or a time is a
  record in the Ledger. An Instance is written only over the turn it was
  read at, so two nodes taking a turn of one Instance never both write.
- **Two tables of their own** in the runtime database: Process Instance and
  Correlation (`persist::storage`'s `instance`).

### 5. Correlation sets, cluster-wide, and the one Sequence

The owner, 2026-10-22: *Correlations should be definable, like in BizTalk.
Default would be the receive port, if one would like to broaden it it
should be able to use promoted values in a message or context values*;
*As long as the correlation sets are cluster wide*; then, of the default,
*every receive location should by default be end to end treated. Not the
receive port, unless opened up by correlation sets to support multiple
processing through Xmip*; and, replacing the drafts before it, *A default
correlation set is its receive location name. There might be more streams,
files, pushing at that receive location. Default one stream, message,
journey at a time. Put it in the ledger if it is not processed now. If I
want to open up for parallelism I can use context values like Receive Port,
Work Process, Send Port, Message and Journey context values. I can widen
and strangle parallelism at any configurable point*; *Equal values in a
correlation set (aka hashtable) go in the same queue, different values go
parallel depending on the value in the correlation set*; and *Of course that
is why the stages exist, Receive Location, Receive Port. It is up to Xmip to
work as specified. A Receive Location can work on its own when the
Correlation Set value is only Receive Location. When there is a more
complicated Correlation Set, Xmip is the tool.* His two examples: an order
*can be processed per client requesting an order*; an update of all the
merchandise *Xmip should process one at a time because the person updated
all the merchandise is hacking away not knowing of the consequences*.

- **`[[correlation_sets]]`**, declared once in the cluster's `xmip.toml`:
  `name`; `keys` — `receive-location`, `receive-port`, `work-process`,
  `send-port`, or a Message Context value by the name a filter reads it by,
  promoted properties among them; and `on_failure`, `block` where it says
  nothing, `skip` to let the rest pass (the owner, 2026-10-22: block by
  default, skip as an option). A Journey Context value is one of three,
  `journey:origin`, `journey:subscription` and `journey:previous`
  (amendment 2026-10-27). configure refuses an undeclared set, one declared
  twice, one with no key and a key that is no key word, at validation and as
  a node starts.
- **A point names a set** by `correlation_set`: a Receive Location, a
  Receive Port, a Work Process or a Send Port. A BPMN start or receive names
  the set it takes Messages by, `<xmip:correlate set="…"/>`: the start
  initializes it, a later step follows it, and a process may follow several.
  A Send Location names one too (amendment 2026-10-27).
- **A Receive Location that names none goes one Stream at a time**, keyed by
  its own name: the merchandise update needs nothing configured, and
  `correlation_set = "PerClient"` keyed by `context:Client` spreads orders
  per client.
- **The Sequence is one mechanism** (`runtime::sequence`): a queue in the
  Ledger per point and key, named by the point and the key's values in full
  — `<cluster>/sequence/<point>/<name>/<set>/<values>` — its identifier
  named from that text and the text kept beside every place, so two keys
  share a queue only where every value is equal. A place is taken in the
  write that brings work to the point; work there goes on only while it
  holds the first place, and what does not waits in the Ledger, holding no
  thread. A Receive Location's and a Receive Port's sequence holds the
  Stream end to end: its origin holds the place until the last Journey born
  from it ends, which Xmip Storage counts in the writes that open and end
  them (the Journey facts `origin` and `open`). A Work Process's and a Send
  Port's holds the Journey while it is at that point.
- **The Send Port's `execution_style`, `order_key` and `on_failure` are
  deleted**, and a Work Process's `execution_style` with them: a Send Port
  that must send one at a time names a set keyed by `send-port`, and the
  send scan's own ordering (`send_step/scan.rs`'s `in_sequence`) is deleted,
  so ordering has one implementation.
- **What a Location does on its own.** A Stream's place in its Receive
  Location's sequence is taken in the Publication's own write and counted in
  the writes that open and end its Journeys, so the default costs no write
  of its own. Whether a Stream heads its sequence is one Ledger read, once
  per Stream on each node that takes a step of it: a place that heads its
  sequence heads it until it is let go, so a node remembers what it has seen
  head and asks again of nothing (`sequence::heads`). No Location keeps the
  promise end to end alone — its Stream's send may run on another node — so
  none passes the Ledger's sequence by: the cluster-wide promise is never
  traded for a read.
- **The receive order** (the owner, 2026-10-22: *Every received stream must
  check in, from what Receive Location, Receive Port. It has to propose its
  identity, be authenticated, authorized, promoted, Correlation Set
  populated, then we can queue the message in the fashion it needs to be
  queued*, and *Identify, Authenticate and Authorize. Those are different
  uses*): check in, Identify, Authenticate, Authorize, Prepare and Message
  creation, Contract and validation, promotion, the correlation set's key
  populated, queued. Nothing joins a sequence before its key is populated.

Provenance: the rulings quoted are the owner's, 2026-10-22. The program's
steps, the extension elements' names (`urn:xmip:process:1`, `xmip:call`,
`xmip:debatch`, `xmip:batch`, `xmip:correlate`, `urn:xmip:expression`), the
key words, the queue names, the turn's form and section 13's shape are the
assistant's, each the owner's to strike.

## Amendment, 2026-10-27: a Debatch is a unit of its own capability

The owner, 2026-10-27, agreed as proposed: a splitting unit declares the
capability `debatch` — the seventh beside `prepare`, `promote`, `demote`,
`transform`, `work-process` and `validate` (`abi::UnitCapability`) — and
serves `receive` and `process` alone, which configure holds a unit's
stages to as it holds Promote to `receive` and Demote to `send`
(`configure::modules::fixed_stages`). A fifth list of calls,
`[[debatches]]`, is attached on receive by `debatch = "<entry>"` and
called from a Work Process by `xmip:debatch` (clause 3 of the amendment of
2026-10-22). The amendment of 2026-10-22's *a Work Process's flow, a
Debatch, may serve receive as well as process* is read so: a Debatch is a
`debatch` unit, never a `work-process` one. What a debatch does with its
records is ADR-0031's, amendment of this date.

## Amendment, 2026-10-27: correlation sets are how Xmip does exclusiveness

The owner, 2026-10-27: *So lets work on that, that is exclusiveness! Way
more important than parallelism.* Clause 5 of the amendment of 2026-10-22
is Xmip's exclusiveness: one winner per artifact; by default one Stream,
Message or Journey at a time per Receive Location, cluster-wide, from read
until it leaves through Send; correlation sets open or narrow it at any
point; a failure blocks until Retry or Dismiss, or skips. Built the same
day, each recorded in ADR-0024's amendment of this date: a Send Location
names a set; `journey:origin`, `journey:subscription` and
`journey:previous` key one; a Stream's Journeys take their places at
their destinations once the Stream heads its own sequences; a claim
carries a fence that grows with every holder and every Storage epoch; and
sets taken in crossing order are refused. Resilience and exclusiveness
becoming pluggable capabilities is open problem 54.
