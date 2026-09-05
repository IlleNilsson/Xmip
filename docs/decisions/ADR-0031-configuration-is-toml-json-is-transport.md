# ADR-0031: Configuration is TOML; JSON is transport

- Status: Accepted
- Date: 2026-09-05
- Related: ADR-0011 (module and repository naming), ADR-0030 (prefix external
  names), ADR-0028 (the Xmip Playground), ADR-0029 (observation has history)

## In brief

- Theme: The shape of the estate
- Subject: What Xmip configures itself in, and what it moves data in
- Name: Configuration is TOML; JSON is transport
- Order: 6
- Concepts: Configuration, TOML; Transport, JSON

**Xmip configures itself in TOML and never in JSON. JSON is for transport —
content in memory or on the wire — and never for configuration.** The estate's
own files on disk are TOML; JSON that appears does so as data being carried or
validated, not as a file Xmip reads its settings from.

## Context

The owner's rule, stated repeatedly across 2026-09-04 and 2026-09-05 and each
time after the assistant reached for JSON where it did not belong: *"Xmip does
not use JSON for configuration at all, anywhere"*; *"there will always be JSON
transport"*; *"we only want JSON in memory or on the network, not as
configuration."* It is written down here so it is not re-litigated a fifth time.

The estate already lived this before it was recorded: `architecture.json` was
deleted for `architecture.toml`, and the .NET hosts read `xmip.gui.toml` through
a TOML configuration provider rather than `appsettings.json`.

## Decision

### 1. Configuration is TOML

Everything Xmip reads its own settings from is TOML: `architecture.toml`, node
configuration, `xmip.gui.toml`, and any file that follows. There is no JSON
configuration anywhere in the estate, and none is to be added.

### 2. JSON is transport

JSON is for data in motion — content on the wire, a message body, a payload a
Contract validates. That is the case the estate keeps JSON for, and it is always
available: Xmip has to speak JSON to the world.

### 3. On disk is TOML, even for data the estate writes for itself

A file the estate persists — configuration or its own runtime data, like the
Playground's snapshot and history — is TOML. JSON is reserved for what lives in
memory or on the network. A persisted file is neither, so it is TOML. (ADR-0029
clause 5 applies this to the history file.)

### 4. What is not Xmip's to choose

Two kinds of JSON are outside this rule because Xmip does not own their format:

- **Foreign tooling files.** `global.json`, `launchSettings.json` and
  `packages.lock.json` are .NET SDK artifacts in fixed formats. They are not
  Xmip configuration and cannot be TOML; they stay as the SDK requires.
- **Content that happens to be JSON.** A Stream whose payload is JSON is data
  being carried or validated, not a file the estate configures itself from —
  clause 2, not a violation of clause 1.

## Consequences

- A new setting goes in a TOML file; a new persisted artifact is written in TOML;
  a new data exchange with the outside may be JSON.
- The distinction to check is not the format but the role: is this Xmip reading
  its own settings, or Xmip moving data? The first is TOML, the second may be
  JSON.

## Provenance

The rule is the owner's, stated across 2026-09-04 and 2026-09-05 and finally
*"write every decision down."* Clauses 1 to 4 are the assistant's drafting of it,
on that instruction.
