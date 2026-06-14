# Xmip.SendPort

`Xmip.SendPort` is an organizational outbound concept.

A SendPort contains one or more SendLocations.

The first SendLocation that succeeds completes the SendPort.

There is no primary or secondary SendLocation terminology.

## SendPortDefinition

A SendPortDefinition is configured in TOML.

It declares:

- send port name,
- ordered SendLocation list,
- retry policy where applicable,
- audit, tracing, and tracking settings,
- send behavior policy.

## SendPortInstance

A SendPortInstance is the runtime execution of a SendPortDefinition for a Message.

A SendPortInstance evaluates SendLocations in configured order.

A successful SendLocation completes the SendPortInstance.

Failed SendLocations before the successful one are recorded as warnings.

If all SendLocations fail, the SendPortInstance fails.

## SendLocationDefinition

A SendLocationDefinition is a concrete outbound delivery binding.

It declares:

- send location name,
- Handler reference,
- Handler configuration,
- endpoint or destination configuration,
- identity and authorization configuration,
- retry classification behavior where applicable.

## SendLocationInstance

A SendLocationInstance is the runtime attempt to deliver a Message through a SendLocationDefinition.

It records:

- message id,
- interchange chain,
- send port instance,
- send location name,
- attempt result,
- warnings or failure details.

## SendPortGroup

A SendPortGroup contains multiple SendPorts.

A SendPortGroup is an organizational grouping of outbound delivery options.

## Rule

A SendPort is completed by one successful SendLocation.

A SendPortGroup contains multiple SendPorts.
