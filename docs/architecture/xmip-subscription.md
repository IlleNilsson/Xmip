# Xmip.Subscription

`Xmip.Subscription` looks for patterns in the message flow and creates an action when a pattern matches.

A Subscription is not only a static filter.

It is a configured pattern-to-action rule.

## Definition

`SubscriptionDefinition` is configured in TOML.

It declares:

- subscription name,
- pattern definition,
- match scope,
- action to create,
- priority where applicable,
- audit, tracing, and tracking settings.

## Instance

`SubscriptionInstance` is the runtime evaluation of a SubscriptionDefinition against a message flow.

A SubscriptionInstance records:

- evaluated message,
- evaluated interchange chain,
- matched or not matched,
- created action when matched,
- evaluation time,
- outcome.

## Pattern

A pattern may be based on:

- promoted properties,
- message metadata,
- section metadata,
- receive location,
- receive port,
- contract,
- message type,
- interchange chain,
- previous messages in interchange history,
- process state where policy allows.

## Action

When a Subscription matches, Xmip creates an action.

Examples:

- start a ProcessInstance,
- resume a ProcessInstance,
- send to a SendPort,
- route to a SendLocation through a SendPort,
- assign a message,
- transform a message,
- move to a dead message queue when required.

## Rule

A message that enters Xmip must match one or more subscriptions or reach a configured terminal outcome.

If no valid subscription or terminal outcome exists, Xmip moves the message to the Xmip Dead Message Queue with its metadata, message state, and interchange chain preserved.
