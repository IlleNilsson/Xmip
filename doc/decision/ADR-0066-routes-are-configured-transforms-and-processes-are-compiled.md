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
- Concepts: expression; compiled at start; compiled at design time

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
