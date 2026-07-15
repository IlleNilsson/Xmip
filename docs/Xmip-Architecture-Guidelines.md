# Xmip Architecture Guidelines

## Purpose

This document is the working discipline for Xmip architecture and implementation. It exists to prevent terminology drift, responsibility overlap, premature invention and implementation concepts leaking into the architecture.

It is not a replacement for discussion. It is the reference used during discussion, coding and review.

## 1. Use Xmip concepts first

Before introducing a new concept, first determine whether an existing Xmip concept already owns the responsibility.

Examples:

- Contract is the Xmip concept. XSD, JSON Schema, RegEx, FHIR profiles and other technologies may implement a Contract.
- Xmip Process is the Xmip concept. BPMN 2.0 is its declaration foundation.
- Routing is the Xmip concept. DMN supports Subscription evaluation.
- Transport is the Xmip concept. FILE, FTP, HTTP, MLLP and others implement transport capabilities.

A technology name must not silently replace the architectural concept.

## 2. Separate Identity from identifiers

Identity is a security concept.

An Actor requires an Identity to perform an Action with a Message or against a protected Xmip or external resource. The Identity must be authenticated and authorized for that Action.

Examples of record identifiers:

- message_id
- journey_id
- interchange_id
- section_id
- cluster_id
- node_id
- receive_port_id
- receive_location_id
- process_id
- send_port_id
- send_group_id
- send_location_id
- contract_id
- artifact_id

These identifiers support uniqueness, persistence, correlation and relationships. They are not security Identities and cannot be authenticated or authorized.

Rule:

> An Actor has an Identity. An Xmip record or artifact has an `*_id` or another explicit identification designator.

## 3. Determine Actors by Action

An Actor is something that performs an Action and therefore acts under an authenticated and authorized Identity.

Known Xmip Actors include, subject to the Action being performed:

- Receive Location
- Xmip Process
- Send Location
- Host Process
- Human administrator, developer, operator or other user
- External application, service or Party interacting with Xmip

Do not classify something as an Actor merely because it exists in the model. Ask:

1. Does it perform an Action?
2. Does the Action affect a Message, Xmip state or a protected resource?
3. Under whose Identity is the Action performed?
4. What Authentication and Authorization are required?

Receive Ports, Send Ports, Send Groups, Contracts and similar artifacts have identifiers. They are not automatically Actors merely because they participate in configuration or ownership relationships.

## 4. Preserve Message creation rules

A Message is created only through an established Xmip creation path:

- A Receive Port creates the initial Message after one or more Streams arrive through a Receive Location.
- An Assignment creates a new Message.
- A Transformation creates a new Message.

Routing, Scheduling, Eventing, Reporting, Observer and other supporting domains do not create Messages merely because they need to communicate or trigger work.

A new Message keeps the appropriate lineage, including the interchange_id according to the Message model.

## 5. A Message goes on a Journey

Journey records the past and current history experienced by a Message.

Journey has a journey_id as a record identifier. It has no security Identity and no execution authority.

Journey does not:

- route the Message;
- execute a Process;
- select a Send Location;
- create branches;
- decide failure;
- own retries;
- select a Composite response.

Receive, Routing, Process, Send and other execution domains record relevant facts into the Journey.

Journey and Auditing are related but distinct:

- Journey records what the Message experienced.
- Auditing records authoritative evidence of Actions, Actors, identities, authorization and changes.

## 6. Keep execution responsibilities separate

Xmip has three first-class execution actions:

- Receive
- Process
- Send

The ownership boundaries are:

- Receive Location performs physical receipt of Streams.
- Receive Port creates the initial Message into Xmip.
- Xmip Process performs process logic declared through BPMN 2.0.
- Routing publishes Messages, owns Subscriptions, evaluates Subscriptions and dispatches matching Subscribers.
- Send Port owns logical delivery through its ordered Send Locations.
- Send Location performs physical delivery.
- Send Group is a collection of Send Port references and owns none of them.

Receive and Send may transform but do not assign. Assignment belongs to Xmip Process semantics.

## 7. Routing terminology is fixed

`xmip-routing` contains:

- xmip-publishing
- xmip-subscriptions
- xmip-subscription-evaluation
- xmip-response-routing

Rules:

- Messages are published.
- Subscriptions declare interest.
- Path delivers a value required by a Subscription evaluation.
- Path does not inspect for a business purpose, decide or route.
- DMN supports evaluation semantics but does not own Routing or Subscriptions.
- Routing may resolve zero, one or many Subscribers.
- Subscribers may include Xmip Processes, Send Ports and Send Groups.
- Composite response routing preserves the return path to the originating Receive Port and Receive Location.

## 8. Send terminology is fixed

Use Send Group, never Send Port Group.

A Send Port owns an ordered list of Send Locations.

There are no Primary or Secondary Send Locations. The first Send Location that succeeds completes the Send Port. Earlier failed attempts remain operationally visible.

Resilience determines retry and timeout behavior. Sending owns ordered Send Location semantics.

## 9. Exclusiveness is an architectural domain

Exclusiveness applies to Receive, Process and Send.

Scopes are:

- Cluster
- Node
- Process
- Resource

Examples:

- An IP protocol may require Process-scoped exclusiveness.
- A file or another singular resource may require Resource-scoped exclusiveness.

Exclusiveness determines whether concurrent execution is permitted. It owns boundaries, holders and leases.

Failure is not determined merely because Exclusiveness is unavailable. Resilience determines whether retries or timeout produce final failure.

## 10. Time uses existing standards and domains

Xmip does not introduce a separate general Scheduling architecture when BPMN and existing execution domains already cover the requirement.

- BPMN 2.0 owns timers, waits, scheduled continuation and process time semantics.
- A timed Receive Location activation remains part of Receiving.
- Retry delays and timeout policy remain part of Resilience.
- Routing remains Message-based and uses DMN for Subscription evaluation.

Do not invent internal Events as a substitute for Message flow.

## 11. Eventing is external

`xmip-eventing` delivers Events and notifications to authorized external Parties or observers.

Internal execution between Receiving, Processing, Routing and Sending remains based on the established Xmip Message and invocation contracts.

Eventing is not an internal task bus.

## 12. Reporting is not reports

- xmip-reporting creates reportable data.
- xmip-report is an output produced from reportable data.
- Xmip remains an integration and messaging platform, not a GUI or business-intelligence platform.

Observer and Reporting operate near real time, not real time, so they do not slow core execution.

## 13. Runtime coordinates; domains own behavior

`xmip-runtime` coordinates execution and recovery. It must not absorb domain responsibilities merely for convenience.

Runtime does not own:

- BPMN semantics;
- DMN semantics;
- Message creation rules;
- Routing declarations;
- Send Port semantics;
- Exclusiveness policy;
- Resilience policy;
- Contract semantics.

## 14. Keep xmip-core small

`xmip-core` contains stable domain primitives such as identifiers, Message, Stream references, Journey, action types, outcomes, versions and time primitives.

It must not become a dumping ground for:

- protocol implementations;
- queueing;
- Exclusiveness stores;
- Process engines;
- Routing engines;
- persistence implementations;
- obsolete prototypes.

## 15. Pre-1.0 repository discipline

Xmip is pre-1.0. Git history is the archive.

Remove code that is:

- obsolete;
- outside the current architecture;
- an abandoned prototype;
- no longer referenced;
- retained only for backward compatibility that Xmip has not promised.

Do not preserve architectural mistakes as compatibility burdens before 1.0.

Build only the basic workspace until the fundamentals are stable. Additional environment and profile builds are added when they serve a current engineering need.

## 16. Decision discipline

Before freezing or coding a proposal, perform this check:

1. State the Xmip concept using current terminology.
2. Name the owning domain.
3. State what the domain owns.
4. State what it explicitly does not own.
5. Identify the Actor and Identity for each Action.
6. Identify the `*_id` for each record or artifact.
7. Check Message creation rules.
8. Check Journey and Audit recording requirements.
9. Check whether BPMN, DMN, Contracts or another accepted standard already supplies the declaration model.
10. Check for contradiction with previously frozen decisions.

If a contradiction remains, stop and discuss it before coding.

## 17. Correction discipline

Either the user or assistant may identify a mistake. Correction is part of the engineering process.

When a mistake is found:

1. Name the incorrect statement precisely.
2. Replace it with the corrected rule.
3. Identify affected architecture, documentation and code.
4. Update the frozen guideline or domain document where necessary.
5. Refactor or remove conflicting code before adding more behavior.

Do not defend a wording or implementation that contradicts Xmip merely because it already exists.

## Governing principle

> Use stable Xmip concepts, give each responsibility one owner, require authenticated and authorized Identity for Actors, use explicit identifiers for records and artifacts, and do not invent a new domain when the existing architecture or an accepted standard already provides the answer.
