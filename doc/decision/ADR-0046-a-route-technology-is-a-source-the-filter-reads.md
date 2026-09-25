# ADR-0046: A route technology is a source the filter reads

- Status: Accepted
- Date: 2026-09-10
- Amended: 2026-09-24 — a `Null` is absent and bytes are refused, under `X`
  and `context:X` alike, through one `route::routable`
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
