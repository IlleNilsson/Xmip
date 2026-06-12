# Xmip Persistent Audit Directive

Xmip shall support a persistent audit directive.

The directive can be configured in TOML, for example on a Receive Location Definition.

Purpose:

```text
Audit this Receive Location and every Message and Interchange Chain that starts there.
```

## Behavior

When the directive is active, Xmip carries audit intent as runtime metadata on the Message and its Interchange Chain.

The directive applies through:

- receive,
- accept,
- assignment,
- transformation,
- process execution,
- subscription,
- pass on,
- pickup,
- send,
- retry,
- failure,
- leaving Xmip.

When active, all lifecycle actions for the affected Message and Interchange Chain are audited.

This is stronger than the default mandatory audit events.

## Scope

The directive is persistent runtime metadata.

It is not only a log setting.

It is not only a UI filter.

It is not only a diagnostic flag.

## Mandatory audit remains

Regardless of this directive, Xmip always audits mandatory lifecycle events and failures.

The persistent audit directive adds deeper auditing for configured flows.
