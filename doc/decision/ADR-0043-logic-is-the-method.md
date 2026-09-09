# ADR-0043: Logic is the method

- Status: Accepted
- Date: 2026-09-08
- Related: ADR-0010 (contract and transport repository boundaries, decision 9),
  ADR-0014 (operator surfaces, amendment 2026-08-26 retiring `xmip-core-webapi`),
  ADR-0042 (contracts), doc/planning/open-problems.md problem 6
- Resolves: open problem 6

## In brief

- Theme: Modules and the boundary
- Subject: What the Logic capability is, in one sentence, and why it is not
  process
- Name: Logic is the method
- Order: 6
- Concepts: Logic; operation; invocation; outcome; the method axis

**A Logic technology turns a Stream that arrived on a transport into a named
operation with typed arguments, and an operation's result back into a Stream,
using a contract to type both. SOAP does it with a WSDL, the HTTP API with an
OpenAPI document, gRPC with a protobuf service. Transport moves the bytes,
process orders the work, contract types the content; Logic owns the method —
which operation a Stream asks for, what its arguments are, and how an answer
or a fault travels back on the same reply channel.**

## Context

ADR-0010 decision 9 created `xmip-core-logic` for "method and operation
semantics" and ADR-0014's amendment retired `xmip-core-webapi` into it, but the
capability stayed a six-line placeholder and open problem 6 held it there:
*state the trait in one sentence; if it cannot be stated without describing
`process`, fold it into `process`.* On 2026-09-08 the owner asked where the
SOAP, Web API and gRPC repositories were. They did not exist because the
sentence had not been written.

## Decision

### 1. The sentence

The one in brief. It names process nowhere: process decides what happens to a
Message and in what order; Logic decides what a Stream on a transport *means*
as a call. The test in problem 6 passes, so Logic stays a capability.

### 2. The trait, in both directions

`Logic` has four methods and every technology implements all four
(ADR-0010's direction neutrality applied to methods):

- Receive side: `invocation(Arrival) -> Invocation` reads which operation a
  delivered Stream asks for, with its arguments as a Stream and its parameters
  beside them; `reply(Invocation, Outcome) -> Reply` writes a result or a
  fault the way the caller expects it back.
- Send side: `request(Invocation) -> Request` writes what the transport must
  send; `outcome(Invocation, Reply) -> Outcome` reads what the service
  answered.

An `Arrival` and a `Request` are the same four things — target, method,
headers, body — so a Logic technology never sees a socket. The transport
delivers one and carries the other.

### 3. Three technologies, each its own repository

`soap`, `http-api` and `grpc`, mounted directly under `xmip-core-logic`
(ADR-0016 as amended). Each names the operation in its own terms — the Body's
first child, a method and path or an `operationId`, `/package.Service/Method`
— and each names the contract that types the arguments: `xml-schema`,
`json-schema`, `protobuf`. The `wsdl`, `openapi` and `protobuf` contracts, when
they land, replace those defaults with the service's own description.

## Consequences

- `xmip-core-logic` holds the trait and its shapes; `xmip-core-logic-soap`,
  `-http-api` and `-grpc` implement it, each with its own tests.
- Open problem 6 is resolved by option B, keep and define the trait.
- gRPC rides HTTP/2 and the `http` transport speaks HTTP/1.1 today. The gRPC
  technology frames and names, which is the same on both; the connection is
  the transport's to grow.
- `matter` stays declared and unbuilt under Logic.

## Provenance

The question and the instruction to build are the owner's, 2026-09-08: *where
are SOAP, Web API and gRPC repos?* and *so create the missing repos and
modules.* The sentence was the assistant's proposal in answer, put to the owner
before building; the trait's four methods and the consequences are the
assistant's drafting of it.
