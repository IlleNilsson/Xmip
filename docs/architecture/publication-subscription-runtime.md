# Xmip Publication and Subscription Runtime

## Purpose

This document describes the current understanding of publication and subscription behavior inside Xmip.

## Subscription

A Subscription is an Artifact Definition.

A Subscription contains rules.

When those rules evaluate true at runtime, the Subscription causes runtime action according to its Artifact Definition.

## Subscription Instance

A Subscription Instance is runtime metadata attached to a message journey.

Subscription Instances become part of the traceable history of the message.

## Publication

Publication is a runtime behavior.

Publication may cause additional Subscription rules to be evaluated.

Publication is not limited to leaving Xmip.

A publication may remain inside Xmip and continue message processing.

## Message flow

Conceptually:

```text
Message
    -> Subscription evaluation
    -> Action
    -> Publication
    -> Subscription evaluation
    -> Action
    -> Publication
```

This sequence may continue until the message:

- leaves Xmip,
- completes processing,
- waits for additional activity,
- fails,
- is recovered.

## History and lineage

As publications occur and Subscription rules evaluate, Subscription Instances accumulate.

The resulting chain provides lineage, diagnostics, traceability, preservation support, and recovery support.

## Important rule

Not every action is a Subscription.

A Subscription that evaluates true causes runtime action because of its Artifact Definition.

That action may publish.

The resulting publication may cause additional Subscription evaluations.
