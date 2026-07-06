# Content Handlers

Content Handlers are one of the central concepts in Xmip.

Xmip is stream-first. A Content Handler shall not deserialize more of a stream than is required by the current action.

After transport-level identification and authorization, a Content Handler may step in at several stages of execution. It can identify content, create message sections, promote properties, validate content, inspect content, serialize content, or deserialize only the parts needed by the current step.

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

## Content Handler responsibilities

A Content Handler may support one or more of these operations:

```text
identify      determine whether the handler recognizes the stream
inspect       read enough of the stream to describe it
create        create message section metadata and stream references
promote       extract selected properties as far and as fast as needed
validate      verify content against a contract when configured
serialize     write interpreted content back to a stream
materialize   deserialize only the requested part or shape of the stream
```

`materialize` is intentionally not called full deserialization. Xmip should avoid full deserialization unless a specific action requires it.

## Rule

Content Handlers must be lazy and stream-preserving.

They should promote as fast and as far as needed, then stop. The original stream remains referenced by the message section unless a transformation, assignment, or serialization step produces a new stream.
