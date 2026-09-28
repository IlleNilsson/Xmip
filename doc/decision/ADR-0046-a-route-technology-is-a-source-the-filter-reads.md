# ADR-0046: A route technology is a source the filter reads

- Status: Accepted
- Date: 2026-09-10
- Amended: 2026-09-24 — a `Null` is absent and bytes are refused, under `X`
  and `context:X` alike, through one `route::routable`
- Amended: 2026-09-26 — a filter is one line of the expression language
  (ADR-0066), a missing value is unknown, and `expression` is retired
- Amended: 2026-09-27 — a technology compiles a name once and reads the
  compiled form per Message; only the names the filters use are gathered
- Related: ADR-0013 (the journey model, publication and subscription),
  ADR-0043 (Logic is the method — the same shape of decision for another
  capability), ADR-0044 (a technology shares through its capability),
  doc/planning/open-problems.md problem 10 (no repository for a capability
  whose trait is unsettled)

## In brief

- Theme: Modules and the boundary
- Subject: What the eight route technologies are, and the trait they implement
- Name: A route technology is a source the filter reads
- Order: 7
- Concepts: Source; promoted property; the prefix; route technology

**A Subscription's filter names properties. Each property is read from one
source, and a route technology is one source: `context` reads a context value,
`content` follows a path into the content, `contract` names the contract the
content is bound to and the type it announces, `expression` evaluates a
predicate over other properties, `header` reads what the transport delivered
beside the bytes, `metadata` reads what the Message knows about itself,
`party` reads who sent or will receive it, and `regex` extracts a capture from
any text value. The prefix on a property names its source; no prefix is
context, which is what routing has always read. The capability owns the split
and the gathering; a technology owns one reading.**

*Amended 2026-09-26: seven. `expression` is retired, because a filter is
itself one line of Xmip's expression language (ADR-0066).*

## Context

`xmip-core-route` matches a Message's promoted set against every Subscription
and explains each decline. The promoted set came from the context alone. The
manifest had declared eight technologies under `route` since ADR-0010 without
a description, a maturity or a trait, and the estate map showed them as
declared, not built. Problem 10's lean, applied in ADR-0043 for Logic, is that
no technology repository is created until its capability's trait is settled
and stated in one sentence. On 2026-09-10 the owner asked for everything
declared to be sorted; the sentence above was put to him first and agreed.

## Decision

### 1. The sentence

The one in brief. A route technology does not decide anything: it reads. The
decision stays with the Predicate and the reasoning stays with the Routing.

### 2. The trait

`Source` has two methods, and every technology implements both:

- `technology()` — the manifest leaf, which is also the prefix a property
  carries: `content:order.total`, `header:http.content-type`,
  `metadata:generation`, `party:sender`.
- `read(&Message, name)` — the value of `name` for this Message, or `None`
  when the Message has no such thing. `None` promotes nothing, and a filter
  over nothing declines with its reason, as it always did. An error is for a
  name the technology cannot read at all. What counts as "no such thing" for
  a context value is settled by the amendment of 2026-09-24 below.

`promote(&Message, sources, properties)` in the capability splits each
property, asks the source whose technology it names, and adds what came back
to the promoted set that context always fills. A property that names a
technology no loaded source provides is an error: a filter that cannot be
read is a configuration mistake, not a decline.

### 3. Eight technologies, each its own repository

Mounted directly under `xmip-core-route` (ADR-0016 as amended). `content`
depends on `xmip-core-path` and the path technologies it drives, `dot` and
`jsonpath`; `expression` on `xmip-core-path-predicate` and, for the reader it
implements, `xmip-core-contract`. The rest read the Message and its context
and depend on the capability, message and context alone: `contract` reads
the section's binding and needs nothing from the contract crate, and `party`
reads the party id the runtime promotes (`xmip.party`) and needs nothing from
the party crate. The one rendering of a context value as filter text,
`route::text_of`, lives in the capability (ADR-0044), never in a sibling;
since the amendment of 2026-09-24 every reading goes through `route::routable`
beside it.

## Consequences

- `xmip-core-route` depends on `xmip-core-message`, which the manifest already
  declared and the crate had not taken up.
- A property name with a colon now means something. No existing configuration
  carries one.
- Problem 10's rule is honored: the trait landed before any of the eight
  repositories was created.

## Provenance

The reading of the eight names and the sentence are the assistant's, put to
the owner on 2026-09-10 as a question and agreed as written. The instruction
to build them is the owner's: *sort it all.*

## Amendment, 2026-09-24: a Null is absent, bytes are refused

A property with no prefix and the same property spelled `context:X` disagreed
(open problem 25, row h). The gathering of the whole context,
`Promoted::from_context`, promoted a `Null` as empty text and dropped bytes in
silence, so `exists X` passed on a Null and `X = ""` matched it; the `context`
technology, and `header`, `party` and `regex` after it, read a Null as nothing
promoted and refused bytes. Each technology carried its own copy of that
match.

1. **A `Null` is absent.** A context value that is `Null` is "no such thing"
   in the sense of decision 2, exactly as a key the Context does not hold:
   nothing is promoted, `exists` fails, and no comparison matches it, not
   even one with empty text.
2. **Bytes are refused.** A `Binary` value that a filter names is an error
   with a reason, under `X` and `context:X` alike, because bytes are not
   text. Gathering the whole context leaves a `Binary` value out rather than
   refusing the Message, since no filter need name that key; `promote`, which
   reads the names the filters use, refuses it.
3. **One reading.** `route::routable`, beside `route::text_of` in the
   capability, is the one reading of a value a filter names. Bare `X`,
   `context:`, `header:`, `party:`, `regex:` and the scalar `content:` finds
   all go through it, and the copies in the technologies are gone.
   `contract:type` stays text only, refusing any other type, and reads a
   Null as absent already.

### Provenance of the amendment

The owner's, 2026-09-24, answering the two questions put to him: whether a
Null context value is present or absent in a filter, and whether bytes under
a bare `X` are dropped or refused. *Absent*, and *refused*, under both
spellings.

## Amendment, 2026-09-25: a header is named with its protocol

The owner ruled on 2026-09-24 the question ADR-0019's amendment of that day
left open: a header a transport writes is `<protocol>.header.<name>`, built
once in `context::property::header`. `route/header` read `header:<name>`
from a bare `header.<name>` that nothing wrote; it reads
`header:<protocol>.<name>` from the key that builder makes —
`header:http.content-type` is `http.header.content-type`,
`header:amqp.x-priority` is `amqp.header.x-priority`. The protocol is the
text before the first dot, because a protocol's word has none and a
header's name may; a filter that names no protocol is refused with its
reason, as any property a technology cannot read is (decision 2).

**A name's case counts where the protocol says it does.** HTTP compares
field names without regard to case (RFC 9110 section 5.1), and so do the
mail protocols (RFC 5322 section 1.2.2) and SIP (RFC 3261 section 7.3.1);
Kafka record headers, AMQP application properties, NATS headers and MQTT
user properties compare byte for byte, and `Trace-Id` and `trace-id` are two
headers there. Folding every protocol's names would have merged them. So
`context::property::HEADER_CASE_FOLDING` is the one table of the protocols
that fold, each cited to its clause — `http`, `https`, what rides on HTTP
(`as2`, `as4`, `webdav`, `websocket`, `ssdp`), `smtp`, `imap`, `pop3`,
`mime`, `sip` — and `property::header` lowers the name only for those, the
protocol word itself always, as a URI scheme compares. `route/header` reads
the key that builder makes and compares it exactly, so
`header:http.Content-Type` finds `http.header.content-type` while
`header:kafka.Trace-Id` and `header:kafka.trace-id` are two properties.

The owner's, 2026-09-24: the spelling and that the filter names the
protocol. Where the protocol ends in the filter is the assistant's. That
case folds per protocol, from one table, was the lead's correction of the
assistant's first draft, which folded every protocol, 2026-09-25.

## Amendment, 2026-09-25, later: headers reach the Message Context at arrival

The owner, 2026-09-25, asked where headers enter a Message's context once
their name is one: **the runtime, at arrival.** A transport hands the headers
it received with the arrival — `transport::Arrived` carries them as
properties beside the origin and the bytes — and the runtime writes them into
the Message Context once, as `<protocol>.header.<name>` through
`context::property::header`, case folded where the protocol folds it. No
transport writes into a context. Chosen from two: the runtime at arrival, or
each transport. Not yet built (problem 25, row r).

*Confirmed by the owner, 2026-09-26:* a Message whose Subscription filter
names a value that cannot be read — bytes where text is read, or a prefix no
loaded technology provides — is **refused at arrival**, before any Journey
opens, with the reason and audited, as the runtime has done since problem
25 row n was resolved. Chosen from two: refuse at arrival, or accept it and
let that Subscription not match.

## Amendment, 2026-09-26: a filter is one expression, and `expression` is retired

ADR-0066 clause 2 gave Xmip one expression language and named the three
grammars it replaces. For routing that changes four things; decision 2's
trait and the one reading, `route::routable`, do not change.

1. **The filter is one line of the language.** `route::Predicate`,
   `route::Value` and `route::Test` are gone. A Subscription's `filter` is
   the compiled expression of `xmip-core-path`
   (`path::expression::Expression`), read from its text as the Application
   loads —
   `filter = "MessageType = 'Order' and not Amount > 1000 and
   header:http.x-channel = 'web'"` — and `route::publish` decides it from
   the tree, never parsing again. Each property a filter names is still one
   of this record's prefixed names, read through `route::promote`; a name
   holding what a bare word cannot is written in double quotes
   (`"regex:OrderNo:^INV-(\d+)$" = 12345`).
2. **The literal states the kind.** Where the Subscription used to state a
   value's type (`value = { integer = 1000 }`), the literal's spelling does:
   `Amount > 1000` reads Amount as an integer, `Amount = '1000'` as text. A
   promoted value is still never guessed: it is text until the literal it
   meets gives it a kind, and text that will not read as that kind is said
   in the sentence routing always gave.
3. **A value that is not there is unknown.** A property nothing promoted,
   or one that will not read as the kind asked, is *unknown* with the reason
   routing always gave (`nothing promoted Region`), in SQL's three truths;
   only *true* matches. One behavior changes with it: `not` of unknown is
   unknown, so `not Region = 'SE'` no longer matches a Message with no
   Region — it declines, saying nothing promoted Region.
4. **Seven technologies.** `expression` read a predicate as a property and
   yielded `true` or `false` for a filter to compare: a filter inside a
   filter, and a second grammar. A filter is itself the expression now, so
   `xmip-core-route-expression` is undeclared and unmounted from
   `xmip-core-route`; `starts-with` is
   `like 'x%'`. Decision 3's eight are seven: `content`, `context`,
   `contract`, `header`, `metadata`, `party` and `regex`. The predicate
   technology `expression` drove, `xmip-core-path-predicate`, is retired
   with it: its grammar became the language, which lives in `xmip-core-path`
   itself (ADR-0066).

Held by `xmip-core-route`'s tests (`not` of unknown, the literal's kind, a
filter that does not compile refused as the Subscription is read), each
technology's own, and the runtime's
`a_filter_that_does_not_compile_refuses_the_node_at_start`.

### Provenance of the amendment of 2026-09-26

ADR-0066, accepted by the owner on 2026-09-26, decides the language and
names what it replaces. What routing does with it — the literal's kind
standing for the stated type, `not` of unknown staying unknown, the
retirement of `expression` — is the assistant's reading of that record,
built the same day; each is the owner's to strike.

## Amendment, 2026-09-27: a name is compiled once, and only what the filters use is gathered

The owner's rule of 2026-09-26 — anything on the message path that takes
over a millisecond beyond its load is a defect — found three costs in
decision 2 as built: every `regex:` property compiled its pattern for every
Message, every `content:` property parsed the whole payload again, and the
gathering rendered the whole context to text before reading the names a
filter uses. Decision 2's trait changes shape; what it reads, and the one
reading `route::routable`, do not.

1. **`Source` compiles; a `Reading` reads.** `technology()` stays. `read`
   becomes two steps: `compile(name)`, once, when configuration is read,
   yields a `Reading` — a pattern compiled, a path compiled through the path
   engine, a context key built, a metadata name decided — and
   `Reading::read(&Message, content)` answers each Message from it. A
   refusal of a name is found as it compiles.
2. **The gathering is compiled once.** `route::Gathering` replaces
   `promote(&Message, sources, properties)`: `Gathering::of` takes the names
   every Subscription's filter uses, each once, and compiles each through
   the source its prefix names; the runtime builds it with its `Runtime`,
   never per arrival. `Gathering::promote` reads each compiled name into the
   promoted set, and nothing else: the promoted set is no longer filled from
   the whole context first, so a context value no filter names is never
   rendered, and `Promoted::from_context` is gone. What a filter can see is
   unchanged, because a filter reads only the names it uses.
3. **Content is parsed once per Message.** The first section's content
   reaches every reading as `path::Content`, parsed at most once per form
   however many properties read it; `content:dot:a` and
   `content:jsonpath:$.b` share one JSON parse. `content` reads through the
   one path engine it is configured with, in whichever languages that
   engine carries, and names none itself.
4. **Refusal is where it was.** A name that cannot be compiled — a prefix no
   loaded technology provides, a name its technology refuses — is kept as
   that refusal and refuses each Message at arrival with the reason, as the
   owner confirmed on 2026-09-26; refusing the node at start instead is
   ADR-0066 clause 1's open half.
5. **One extraction, one rendering.** `regex:` extracts through
   `xmip-core-path-regex`'s `Pattern`, the one the `regex` path language
   compiles, so a trailing `#name` picks a named group and a group that took
   no part in the match promotes nothing rather than the whole match. A
   value's text is `ScalarValue::text` in `xmip-core`, which
   `route::routable` calls; `route::text_of` is gone.

Held by `xmip-core-route`'s tests (a name compiled once and ten thousand
Messages read from it, well under a millisecond each on a debug build; only
the names the filters use gathered), `xmip-core-route-content`'s (content
parsed once per Message however many properties read it) and the runtime's
arrival tests.

### Provenance of the amendment of 2026-09-27

The owner's rule of 2026-09-26 on the message path, applied by the
assistant in the performance wave of 2026-09-27; the shape of the trait is
the assistant's, and the owner's to strike.

## Amendment, 2026-09-28: a node refuses an unreadable name as it starts

Point 4 of the amendment of 2026-09-27 named refusing the node at start as
ADR-0066 clause 1's open half. It is built: a running node compiles its
gathering once through the route technologies the program starting it
linked, and refuses to start while a name does not compile
(`Gathering::refusals`, `xmip-core-runtime`'s `startup.rs`). A gathering
used without asking still refuses each Message at arrival with the same
reason.
