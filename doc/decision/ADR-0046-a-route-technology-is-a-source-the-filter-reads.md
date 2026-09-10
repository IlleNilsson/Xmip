# ADR-0046: A route technology is a source the filter reads

- Status: Accepted
- Date: 2026-09-10
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
  carries: `content:order.total`, `header:content-type`,
  `metadata:generation`, `party:sender`.
- `read(&Message, name)` — the value of `name` for this Message, or `None`
  when the Message has no such thing. `None` promotes nothing, and a filter
  over nothing declines with its reason, as it always did. An error is for a
  name the technology cannot read at all.

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
`route::text_of`, lives in the capability (ADR-0044), never in a sibling.

## Consequences

- `xmip-core-route` depends on `xmip-core-message`, which the manifest already
  declared and the crate had not taken up.
- A property name with a colon now means something. No existing configuration
  carries one.
- Problem 10's rule is honoured: the trait landed before any of the eight
  repositories was created.

## Provenance

The reading of the eight names and the sentence are the assistant's, put to
the owner on 2026-09-10 as a question and agreed as written. The instruction
to build them is the owner's: *sort it all.*
