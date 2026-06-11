# Xmip Queue Handler Lineage

Queue handling is a loadable handler family.

Xmip shall not treat MSMQ, RabbitMQ, Apache Kafka, AWS SQS, NATS, JetStream, Redis Streams, or future queue technologies as kernel features.

They are stack-specific handlers in the Queue family.

Conceptually:

```text
Queue family
    Queue
        MSMQ
        RabbitMQ
        Apache Kafka
        AWS SQS
        NATS
            JetStream
        Redis Streams
```

## Family behavior

Queue-family handlers commonly deal with concepts such as:

- queue identity,
- topic identity,
- subject identity,
- stream identity,
- partition identity,
- consumer group,
- durable subscription,
- acknowledgement,
- visibility timeout,
- offset,
- cursor,
- dead-letter behavior,
- competing consumers,
- ordered or unordered delivery.

Not every queue technology supports every concept.

The base Queue family describes shared integration semantics.

Each concrete handler declares what it actually supports.

## Kernel rule

The Xmip Kernel enforces platform rules:

- loadability,
- compatibility,
- trust,
- isolation,
- ownership,
- receive claims,
- audit,
- tracing,
- tracking,
- retry and outcome policy.

The concrete queue handler owns stack-specific behavior.

## Principle

Queue lineage gives Xmip a shared vocabulary for queue-like technologies without baking any queue product into the Kernel.
