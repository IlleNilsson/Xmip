# Content Handlers

Content Handlers are one of the central concepts in Xmip.

Xmip is stream-first. A Content Handler shall not deserialize more of a stream than is required by the current action.

After transport-level identification and authorization, a Content Handler may step in at several stages of execution. It can identify content, create message sections, promote properties, validate content, inspect content, demote properties, serialize content, or materialize only the parts needed by the current step.

## Principle

A stream remains a stream until something explicitly needs interpreted content.

A message can be created with metadata and section references to the original stream. The Content Handler only reads far enough to create the message, identify useful metadata, and promote required properties.

## Typical receive flow

```text
Receive stream
    -> transport identification
    -> authorization
    -> Content Handler identifies content
    -> Content Handler creates message section references
    -> Content Handler promotes required properties
    -> optional validation
    -> Xmip Message created
```

## Typical send flow

```text
Xmip Message selected for send
    -> send artifact selects stream section(s)
    -> Content Handler demotes context and message properties when configured
    -> Content Handler serializes or envelopes only when needed
    -> outgoing stream reference produced
    -> Transport Handler sends stream
```

## Content Handler responsibilities

A Content Handler may support one or more of these operations:

```text
identify      determine whether the handler recognizes the stream
inspect       read enough of the stream to describe it
create        create message section metadata and stream references
promote       extract selected properties as far and as fast as needed
demote        write selected context, promoted, or message properties to the outgoing stream
validate      verify content against a contract when configured
serialize     write interpreted content back to a stream
materialize   deserialize only the requested part or shape of the stream
```

`materialize` is intentionally not called full deserialization. Xmip should avoid full deserialization unless a specific action requires it.

`demote` is the send-side counterpart to promotion. It takes selected Xmip context, promoted properties, or message properties and writes them into the outgoing stream, envelope, metadata, headers, or transport-facing properties as configured by the send artifact.

## Promotion and demotion selectors

Promotion and demotion use selectors, not only flat property names.

Selectors must support named paths, numbered indexes, wildcard indexes, and named indexes.

Examples:

```text
order.customer.name
orders[0].id
orders[n].id
headers['desiredProperty']
envelope.body.items[3]['sku']
```

The runtime stores both the original selector expression and a parsed selector structure so handlers can validate, optimize, and report diagnostics without losing the configured expression.

Selector segment kinds:

```text
Name           path segment such as order or customer
NumberedIndex  numeric index such as [0] or [3]
NamedIndex     named index such as ['desiredProperty']
AnyIndex       wildcard index such as [n]
```

## Rule

Content Handlers must be lazy and stream-preserving.

On receive, they should promote as fast and as far as needed, then stop. The original stream remains referenced by the message section unless a transformation, assignment, or serialization step produces a new stream.

On send, they should demote only the configured properties and serialize only when the outgoing stream requires it.
