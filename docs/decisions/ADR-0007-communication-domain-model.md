# ADR-0007: Communication Domain Model

## Status
Accepted.

## Context
Xmip is not fundamentally an integration engine. Its primary responsibility is to move authenticated, authorized, immutable information between communicating actors. The same communication pattern appears recursively across organizations, companies, fleets, ships, departments, applications, systems, devices and sensors.

## Decision
Xmip adopts a recursive Communication Domain model.

An Actor is any entity that can communicate.

A Domain is an Actor that contains other Actors.

Every Domain follows the same communication rules:

- Parent informs, delegates and commands children.
- Children report, acknowledge and escalate to parents.
- Peers communicate with peers when authorized.
- External communication is policy controlled.

Examples:

Fleet owner
 -> Ship owner
   -> Ship
      -> Captain
         -> Crew
      -> Ship control
         -> Navigation system
         -> Engine system
         -> NMEA 2000 network
            -> Devices
               -> Sensors

The runtime shall not distinguish between these entity types. It only understands Actors, Domains, Identities, Policies and Messages.

## Core responsibilities
- Identity
- Authentication
- Authorization
- Routing
- Subscription
- Orchestration
- Audit
- Persistence
- Recovery

## Consequences
The same runtime architecture applies at every level of the hierarchy. Handlers remain technology specific implementations. Xmip Core remains technology agnostic and communication centric.

## Guiding principle
If a feature does not improve communication between actors or domains, it probably does not belong in Xmip Core.
