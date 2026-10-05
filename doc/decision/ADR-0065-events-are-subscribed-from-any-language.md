# ADR-0065: Events are subscribed from any language, in process and over the wire, from one model

- Status: Accepted
- Accepted: 2026-09-26, the owner, from the options named below
- Date: 2026-09-26
- Related: ADR-0052 (the operator surfaces; the Event subscriptions view, its
  amendment 2026-09-29), ADR-0013 (a Subscription, which this is not; its
  amendment 2026-09-30 shares the act and the order), ADR-0009 (roles: an Operator acts on a
  subscription, an Observer watches), ADR-0012 (the module boundary is a C
  ABI), ADR-0019 (Parties and
  identity), ADR-0027 (the operator boundary, `xmip_operate.h`), ADR-0052
  (code placed once), ADR-0062 (every tool audits), ADR-0063 (Xmip's own
  TLS), `doc/architecture/runtime-model.md` section 17 (Eventing),
  `doc/architecture/observability-model.md`

## In brief

- Theme: What Xmip is at runtime
- Subject: How a program in another language learns what Xmip did
- Name: Events are subscribed from any language
- Order: 15
- Concepts: Event; subscription; the Event wire form; language binding; Event subscription

**One Event model and one subscription rule, in Rust, in `xmip-core-event`.
A program subscribes two ways, both through that one rule: in process,
through a subscribe call in the runtime's C library — C and C++ through the
header, .NET through `Xmip.Abi`, Java through its foreign-function API,
Python through ctypes, and any language that can call C — or over the wire,
in the Event wire form delivered through Xmip's own transports, which any language's
ordinary client receives. Every subscriber is a Party, authorized for what it
may see, and every delivery is audited.**

## Context

The owner, 2026-09-26: *observe and event need some love. Events have to be
subscribable from several languages, like dotnet, java, c, cpp and more.*
`xmip-core-event` was a type and a `publish` trait in 57 lines, with no
subscription and no delivery; `runtime-model.md` section 17 already required
an Event for every Receive, Xmip Process and Send outcome, and receivers
identified, authorized and audited.

## Decision

### 1. Both ways, one model

The owner, from three (both from one model, the C ABI only, the network
only): **both, one model.** A subscription names the Events it wants — by
type, outcome, scope, Party — and the rule that decides whether an Event
matches, and whether this subscriber may see it, is written once in
`xmip-core-event`.

### 2. In process: the C ABI

`xmip_operate.h` gains a subscription: subscribe with a filter, receive
Events (a bounded queue the subscriber drains, or a callback it registers),
unsubscribe. The runtime forwards to `xmip-core-event`, as it forwards every
rule (ADR-0052). Each language binds it once: C and C++ include the header;
.NET's binding is `Xmip.Abi`; Java's is a small package over the
foreign-function and memory API; Python's over ctypes; others as they are
asked for. No binding decides what an Event means.

### 3. Over the wire: the Event wire form on Xmip's transports

An Event leaves Xmip in its wire form, which follows CloudEvents 1.0 (the
CNCF specification, its JSON format and its HTTP, Kafka and AMQP bindings) so
that any language's ordinary client reads it; the standard is named here and
in the event crate's wire module only, and is otherwise hidden, sent by Xmip's own
transports (ADR-0063's rule: Xmip uses its own toolchain) — HTTP (a
webhook), Kafka, AMQP first. The subscriber is a Party with its identity on
the Send side, and delivery is at least once, retried by the resilience
guards.

### 4. Authorized and audited

Every subscriber, in process or remote, is a Party; authorization decides
which Event types, scopes and metadata it may receive (runtime-model section
17). Every delivery and every refusal is audited (ADR-0062).

## Consequences

- `xmip-core-event` grows the Event taxonomy section 17 names, the
  subscription and its matching, and delivery.
- `xmip_operate.h` grows an event section; `Xmip.Abi`, and new Java and
  Python bindings, bind it once each.
- The event capability gains technologies for the wire: the Event wire form over
  HTTP, Kafka and AMQP, each riding the transport of that name.

## Built, 2026-09-26

- **The model and the rule.** `xmip-core-event`: `Event` with the section 17
  taxonomy (`outcome::Outcome`, eight outcomes; `xcore::EventId`), references
  and never content; `filter::Filter::matches`, the one rule, its scope by
  `observe::Scope::contains`. Built by the assistant, 2026-09-26.
- **Authorized and audited (clause 4).** `subscriber::Subscriber` is a Party;
  the gate is `authorize::authorize`, asked once at subscribe as a Send at
  the scope reached, each type as the Contract; a program in this process
  is admitted to nothing for being here (amendment 2026-09-26, below).
  Every subscription, delivery, refusal and forward
  is recorded through `ProgramAudit`, handed to the audit capability's
  keeper (`audit::keeper`, amendment 2026-09-27), so no Event waits for a
  disk and an unsubscribe never does either.
- **In process (clause 2).** `hub::Hub` fans out through a bounded queue per
  subscription and never waits for one; `next` wakes on arrival; `listen`
  calls back on its own thread. `xmip_operate.h` section 11 (ADR-0027,
  amendment 2026-09-26) forwards to `Hub::process` from the runtime's
  `src/ffi/event.rs`; bound once in `Xmip.Abi` (`RuntimeEvents`, and
  `Xmip.Surface`'s `EventFeed`), and beside it in `xmip-core-abi`: C (`c/`),
  C++ (`include/xmip_event.hpp`), Java 21 over the foreign function API with
  `--enable-preview` (`java/`), Python over ctypes (`python/`).
- **Over the wire (clause 3).** `wire::WireEvent` (the JSON format)
  and `binding::Binding` (HTTP, Kafka and AMQP, structured and binary) in
  the event crate; `forward::Forwarder`, at least once, in order, under the
  resilience guards; each of the http, kafka and amqp transports carries a
  `event_wire.rs` presenting the identity configured for the Party.
  The Event Grid transport uses the event crate's wire form. On AMQP 0-9-1 the standard's attributes ride the headers
  table, the equivalent of AMQP 1.0's application properties.
- **Near real time.** Measured on the owner's Windows machine, debug build:
  a publish costs about 1 µs to one subscription; publish to receipt is a
  median of about 40 µs in Rust, 70–100 µs through the C ABI, 0.2–0.3 ms in
  .NET, Java and Python, and 0.3–0.5 ms over loopback HTTP, Kafka and AMQP.
  Every test holds its median under a millisecond beside a plain thread wake
  measured under the same load.
- **Not yet.** The runtime does not publish its own action Events from the
  message path yet, so no operator surface subscribes (`Get-XmipEvent` and
  `xmip event` wait for it); a Forwarder is not yet run by a node from
  configuration.

## Amendment, 2026-09-26: a subscriber hears the cluster

Asked whether a program in a node's own process is admitted for being there,
the owner answered wider: *a program subscribing to events shall receive
events from the cluster, not just a node*, and then: *of course a subscriber
to events has to listen to something. But it is the cluster, not nodes.* A
subscriber listens to the cluster — the cluster's own address, in process
through the cluster's side of the runtime library, over the wire at the
cluster's endpoint — never to a node, and never names one. It receives the
Events of every node in the cluster that match its filter and that its Party
may see; which node answers it is the cluster's business. Two things
follow. Events cross between nodes, so they ride the node-to-node protocol
(problems 17 and 18), mutual TLS as ADR-0063 requires; and no subscriber is
admitted for its place — `SameProcess` goes, and every subscriber, in process
or remote, names its Party and is authorized as one (clause 4).

## Amendment, 2026-09-26: the wire form is hidden

The owner, 2026-09-26: *cloud is not a word we want within the Xmip world*,
and *just hide, encapsulate it. We are offline first.* The standard stays on
the wire (clause 3) and is encapsulated: everywhere Xmip speaks — code, help,
surfaces, records — it is the Event wire form. Delivery assumes no network
beyond the ones the cluster is configured with.

## Amendment, 2026-09-27: audit's keeper, and an unsubscribe that does not wait

Recording without blocking the caller is the audit capability's, not
eventing's: the thread that keeps records in order moved from
`xmip-core-event` to `xmip-core-audit` as `keeper` (`later`, `settle`), and
eventing hands its records to it. Dropping a subscription no longer settles
the keeper — the dropping thread is the program's and a disk is not its
business. A direct `ProgramAudit::record` settles first instead, so a
program's records are kept in the order it made them and the record of its
stop after everything it handed over before.

## Amendment, 2026-09-29: an operator sees every subscription, and pauses, resumes and removes one

The owner: *Now we need operation to have a view of event subscriptions.
Subscriber, Cluster, Node, Action. One should be able to pause, resume and
remove event subscriptions.* What follows is the assistant's drafting, each
point the owner's to overrule.

- **What a hub holds is listed.** `Hub::standing` answers each open
  subscription as `observe::EventSubscription`: the node whose hub holds it and
  its number there, which together name it; the subscriber, by the name its
  Party was declared with (`party::Party`, carried by
  `Subscriber::declared`), and the Party's identifier beside it — a
  subscriber known by its identifier alone is shown by it, and no name is
  made from one; what
  it subscribes to in words (`Filter::said`: every Event, or the types, then
  the outcomes) and the scope it reaches; its state, active or paused; and
  its queue's counts — queued against capacity, delivered, and missed, what
  a full queue refused since it was made.
- **Pause, resume, remove** (`observe::Act`, `Hub::act`, the one place an
  act is applied). Paused, a subscription stays and keeps queuing up to its
  capacity, and nothing is handed over — a drain waits until it is resumed,
  closed or out of time; what a full queue refuses meanwhile is counted as
  missed, as it always was. Resumed, it hands over what queued, waking a
  waiting drain at once. Removed, it is closed and gone from the hub, and
  its holder's next drain, or its listener's thread, finds it closed. Each
  act is recorded in the subscriber's own audit with who took it
  (`event.pause`, `event.resume`, `event.remove`), and an act on a
  subscription that is not there is REFUSED in words. Who may act is the
  surface's to decide by role (ADR-0009): the hub applies what reaches it.
- **How an act reaches the node.** A surface over a live node calls the
  runtime's library in that node's process, as a scope's pause does:
  `xmip_event_subscriptions_v1` and `xmip_event_subscription_act_v1`
  (`xmip_operate.h` section 11), bound as `RuntimeEventSubscriptions`, reached by
  `NativeOperator` and, from another machine, through the web host's
  surface hub (`RemoteOperator`). A surface over a snapshot touches no node,
  and a scope's pause there is declined; a subscription's act is not, because
  its publication says where its publisher takes orders
  (`observe::Publication::orders`): the surface leaves an `observe::Order`
  there through `xmip_order_v1` (section 14), and the node that holds the
  subscription takes it at its next look and applies it as above. The file,
  its place and its shape are `observe`'s alone, one order for an Event
  subscription and a Subscription (amendment 2026-09-30).
- **The snapshot carries the subscriptions.** A node records what its hub
  holds in its snapshot (`Snapshot::record_event_subscription`), a
  publication writes them as `[[event_subscriptions]]`, the Playground's
  cluster and roll merge them as they merge health, and a surface reads them
  through `xmip_publication_event_subscriptions_v1`. None is persisted: a subscription
  lives in its process's hub, and the snapshot says what the hub held when
  it was taken.
- **Every Playground node subscribes two Parties**, through the hub and
  nothing of its own: *operations* hears every Event on the node and is
  called back; *on-call* hears the failures and is drained each round. A
  node raises an Event for each stage it serves whose failing pairs changed
  since the round before, and takes its orders under the directory the
  cluster shares. The subscriptions are real: a paused one is seen to fill.
- **The view.** A fifth view in both GUIs, *Event subscriptions*: subscriber,
  cluster, node, action, then state, queued, delivered, missed and since;
  ordered by any column from its head, narrowed by the scope-pattern box
  over each subscription's node and reach, drilled cluster → node →
  subscription, every step a link carrying the cluster; bounded rows, no
  Virtualize. `EventSubscriptionQuery` (`Xmip.Surface`) is the one drill,
  filter and order every surface asks. An Operator is offered pause, resume
  and remove, each recorded in the host's audit as `event.<act>`; an
  Observer is shown the list and no act. `xmip-cli event-subscriptions`
  lists and, with `--pause`, `--resume` or `--remove` on one named by
  `--location` and `--id`, acts; `Get-XmipEventSubscription` is the one
  cmdlet for the noun, the act a parameter set with `-WhatIf`.
- **Not yet.** No Playground node forwards over the wire, so every
  subscription the view lists is in process. A snapshot lists what its
  publisher last published, so an act left for a node shows within a round,
  not at once.

Provenance: the owner's requirement, quoted; the model, the order
through the publication, the Playground's Parties and the view's form are
the assistant's, for the owner to overrule.

## Amendment, 2026-09-30: every name of the Event kind says Event

The owner asked the same day for a view of the Subscriptions that pick a
published Message up, with pause and resume and no remove (ADR-0013,
amendment 2026-09-30). So that each noun has one name everywhere, every
identifier, export, command and cmdlet of the amendment above that was
called Subscription is named for the Event subscription, the old name
deleted, and the plain name is the Subscription's: `observe::EventSubscription`
(its state `observe::PauseState`, shared with the Subscription),
`Snapshot::record_event_subscription`, `[[event_subscriptions]]`,
`xmip_publication_event_subscriptions_v1`, the handle a subscriber holds
`xevent::hub::EventSubscription`; in .NET `EventSubscriptionRecord`,
`EventSubscriptionList`, `RuntimeEventSubscriptions`,
`EventSubscriptionQuery`, `EventSubscriptionAct`,
`EventSubscriptionOperation` and `IOperatorSurface.EventSubscriptions`; the
view's page and table, `xmip-cli event-subscriptions` and
`Get-XmipEventSubscription`. The act and the order moved to `observe` —
`Act`, `Noun` and `Order` — and are one for both nouns: an Event
subscription takes pause, resume and remove, a Subscription pause and
resume; `xmip_order_v1` replaces `xmip_event_subscription_order_v1`, and
the node's audit action for an act here stays `event.<act>`.

Provenance: the owner's requirement of ADR-0013's amendment; the names are
the assistant's, for the owner to overrule.

## Provenance

**The owner's**, 2026-09-26: the requirement quoted in Context and clause 1,
chosen from the three options named there.

**The assistant's**: clauses 2 to 4's means — the queue or callback shape,
the bindings named, the wire form's standard, at-least-once — each
the owner's to strike.

## Amendment, 2026-10-02: any node is the cluster's door

The owner, 2026-10-02: *Pub/Sub is cluster central. So when external code
expect Subscription Events, they should be able to hook up to any node and
expect events from the complete cluster.* The cluster's endpoint of the
amendment of 2026-09-26 is every node of the cluster: a subscriber connects
to whichever node it reaches and receives the Events of every node that
match its filter and that its Party may see, exactly as it would from any
other. It still never names a node, and a node it connects to is not the
node it hears.

Built, 2026-10-02 (the assistant's drafting, each point the owner's to
overrule): `xmip-core-event`'s `cluster::Cluster` joins a node's hub to the
cluster. Its sync listener (ADR-0067) answers every other member, over Xmip's
mutual TLS (ADR-0063) agreed as `xmip-event/1`, with that node's own Events;
and the node holds one link to each other member, pushing every subscription's
filter down, so an Event crosses only where a filter wants it, once, one hop,
pushed as it is raised — a member answers from its own Events only, so nothing
loops. A Party is authorized where it subscribed; a link presents the node's
certificate and is authorized as a node. Links are held while a member is
followed, subscribers or not, so a subscribe costs one round trip, never a
handshake. A member down is retried on its own link's thread, at most a
second apart, and meanwhile is unheard; what a link's queue refused crosses
as a count and is missed on the subscriptions it matched. A link is the
cluster's, not a Party's: it is not listed among the Event subscriptions and
no operator acts on it, since pausing one would silence a node for every
subscriber at once. Measured on the owner's Windows machine,
debug build, loopback: raised on one node to a subscriber on another, a
median of about 0.4 ms and a 99th percentile under 0.8 ms, against 45 µs on
the node itself — the hop adds about 0.36 ms. Not yet: which nodes are
members, and their sync addresses, is `cluster::Membership`, which a node
fills from Xmip Storage's administration database, and nothing writes or
lists the membership records there yet; no node starts its sync listener or
joins from configuration yet; and the identity a node presents to the other
nodes is not configurable yet (as for Xmip Storage).

Settled the same day, through the lead (the owner's rulings relayed, the
means the assistant's):

- **`SameProcess` is deleted**, with every use, as the amendment of
  2026-09-26 said: every subscriber names its Party and is authorized as
  one. Who may subscribe is one policy and nothing beside it — no second
  Party allow-list: a hub's gate (`gate`) is the `authorize::Authorizer`s it
  is handed (`Hub::authorize_by`), the node's as it starts, or one the
  program hosting the hub takes from the authorize capability — "these
  Parties" is the party technology's `PartyPolicy`, which the Playground and
  every test hand their hub, never a copy of it. Across the C boundary the
  trait is a callback the hosting program hands over —
  `xmip_event_authorize_v1`, answering allow, deny or no opinion of each
  attempt, bound in .NET (`RuntimeEvents.AuthorizeBy`), Java, Python, C and
  C++. `Hub::process` admits nobody until it is handed one.
- **Nothing missing reaches the subscriber silently.** Every delivery
  carries the members not heard now — by which node, the member, since when
  and why, `observe::Unheard` — and a change wakes a waiting drain with no
  Event (`Delivery::unheard`, `unheard_changed`; `xmip_event_batch_unheard_v1`
  for a batch and `xmip_event_unheard_v1` for a listener; `EventDelivery`
  in .NET).
- **An operator sees an unheard node.** Links stay hidden as acts, and every
  surface shows each member a node does not hear as one read-only line
  beside the Event subscriptions — *alpha: not hearing `<node>` since
  `<time>`: `<why>`*, worded once by `observe::Unheard::said` and
  `EventSubscriptionQuery.Line`: in the node's publication
  (`[[unheard]]`), the section 11 list's `unheard`,
  `EventSubscriptionList.Unheard`, `xmip-cli event-subscriptions` (a line,
  and `unheard` in `--json`), `Get-XmipEventSubscription` (a warning), and
  the web's Event subscriptions view.

Provenance: the owner's ruling, quoted; the wording is the assistant's.

## Amendment, 2026-10-05: the bindings are the perimeter

The owner, 2026-10-05, ruled on runtimes inside Xmip's own processes
(ADR-0018, amendment 2026-10-05): *Read it as InProcess with threads is
default true, any other runtime has to be opt in by configuration*; *As long
as they are on the peremiter the are within Xmip Processes, otherwise they
have to be exclusivley invited*; *I said that dotnet runtime was invited
unless excluded*; and *I do not want other runtimes to interfer with
potential perfect Rust code.*

- "In process" in this record means the subscriber's process: a C, C++,
  Java, Python or .NET program loads the runtime's library into itself and
  subscribes through it. Xmip loads nothing of that program. Each is a
  program at the perimeter, calling Xmip from outside, and needs no
  invitation; the bindings in `xmip-core-abi` and
  `verify-event-bindings.ps1` stay.
- What the ruling removed is the other direction: another runtime hosted
  inside an Xmip process. The C, C++, Go, Java and Python contract
  technologies did that and are gone, with the reserved transform and
  process entries in C, C++, Go, Java, Lua, PowerShell and Python (ADR-0042,
  amendment 2026-10-05).
- The JDK, Python and zig stay in `prerequisite.toml`, now for these
  bindings alone; the Go toolchain served only a contract technology and is
  gone.

Provenance: the owner's ruling, quoted; the wording is the assistant's.
