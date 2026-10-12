# ADR-0071: Xmip is reached over MCP through the command line

- Status: Accepted
- Accepted: 2026-10-12, the owner, in the words quoted below
- Date: 2026-10-12
- Related: ADR-0014 (the operator surfaces), ADR-0027 (the operator
  boundary; clause 3, the Xmip URI; clause 4, the scope tree), ADR-0009 (the
  Observer role, amendment 2026-09-06), ADR-0052 (the operator surfaces
  share one model; amendments 2026-09-24 and 2026-09-25), ADR-0053 (a node's
  location), ADR-0062 (every Xmip tool audits), ADR-0067 (a node has one
  address), `doc/planning/market-position.md` section 8

## In brief

- Theme: Operating Xmip
- Subject: How an MCP client reaches a running Xmip
- Name: Xmip is reached over MCP through the command line
- Order: 11
- Concepts: MCP, the Model Context Protocol; `xmip-cli mcp`; Xmip URI as a resource; read only, the Observer's reach

**`xmip-cli mcp` is a Model Context Protocol server: a mode of the command
line, not a new program, and the fifth way into the operator boundary. Its
tools are the command line's read commands and nothing else; its resources
are the scopes, each an Xmip URI, read as an operator drills. It reads only,
and every answer is audited as the command it is.**

## Context

`doc/planning/market-position.md` section 8, 2026-09-23, put a language
model outside the message path and named the step that is credible: *an MCP
server over the read-only operator boundary*. Nothing was built. The owner,
2026-10-12: *What happened to MCP?* — and *It has to be designed and built*.
And the same day, of how: *As we have Uri's into Xmip It should be simple to
get one started.* And, of what it is: *MCP is hardley AI, it just exposes
functionallity* — a protocol any client may speak, not an AI feature; this
record names no AI, and Xmip offers MCP as it offers its other surfaces.

The records already decide most of it. ADR-0014: every operator surface is
.NET and calls the C ABI directly, never through another surface; remote
operation rides shell remoting, and Xmip defines no remote protocol of its
own. ADR-0027: what crosses the operator boundary is health, measurement,
reports and configuration read and validated, every answer with its scope,
and a scope is an Xmip URI on one tree. ADR-0009: the roles are Observer,
Operator and Developer, and the Observer watches and does not act. An MCP
resource is named by a URI, so the scope tree is already a set of resources.

The design was agreed on 2026-10-12 as *started with*: `xmip-cli mcp` over
standard input and output, read only; two questions stay open for widening
it.

## Decision

1. **A mode of the command line.** `xmip-cli mcp` speaks the Model Context
   Protocol — JSON-RPC 2.0, one message a line, on its standard input and
   output, protocol revision `2025-11-25` — to the MCP client that starts it.
   There is no new executable and no new cmdlet. Standard output carries
   protocol messages and nothing else; what the server says of itself goes
   to standard error.
2. **The fifth way in, as the other four.** It calls `Xmip.Surface` and so
   `xmip_operate.h`, as every surface does (ADR-0014), and the surface it
   reads is chosen by the one rule: `--runtime`, `--remote` and
   `--snapshot` on its line, else `xmip.cli.toml` (ADR-0052 clause 1).
3. **The tools are the read commands, exactly.** Each tool is a command the
   line already has, named by its word — `abi`, `status`, `health`,
   `measure`, `list`, `show`, `validate`, `audit` (with `verify`),
   `subscriptions`, `event-subscriptions`, `dead-messages` and `journey` —
   its options its arguments. A call is the line an operator would type,
   parsed and answered by the same code, so a tool and its command cannot
   answer differently. No act exists in MCP that the other surfaces lack,
   and no act is a tool.
4. **The resources are the scopes.** Every scope the surface publishes is a
   resource named by its Xmip URI (`xmip:///<cluster>/node/<node>/…`), and
   the scope tree as built is the resource templates. Reading a resource is
   how an operator drills: the scope's row — its mood, its worst leaf and
   why, its figures — then the rows beneath it, the next URIs to read. A
   URI is one scope; a wildcard is a tool's argument, not a resource.
5. **Every answer carries its scope.** A command's document names the
   scope of every row in it, and a tool's result names the scope it was
   asked at as well.
6. **Read only, the Observer's reach.** Pause, resume, the acts on a
   Subscription, an Event subscription, a dead Message or a failed Journey,
   and `--who` are not arguments of any tool, and a line that would act is
   refused. `probe` is not a tool: loading a library runs its code.
7. **One gate, as the caller.** The caller is the user the process runs as,
   as for every command, and every answer is audited as its command
   (`CommandAudit`, ADR-0062). Nothing in a model's text decides what it
   may do.
8. **Remote is the command line's remote.** On another machine it is the
   same line over SSH (ADR-0014 clause 6): the client starts
   `ssh <host> xmip-cli mcp`, SSH authenticates, and Xmip opens no listener.

## Open

The owner's two questions of 2026-10-12 stay open; the start above answers
neither.

1. **How an MCP client reaches it.** Over standard input and output only — local,
   or over SSH, needing no new listener — or also over HTTP on the node's
   operate listener (ADR-0067)?
2. **What it may do.** Read only, as the Observer — the start — or also the
   Operator's acts (pause, resume, retry, replay), each still gated by the
   caller's role (ADR-0009, amendment 2026-10-06)?

## Consequences

- Built, 2026-10-12, in `xmip-core-cli`: `CommandRun` is the dispatch the
  executable and every tool call share, lifted out of `Program.cs`;
  `McpServer` answers `initialize`, `ping`, `tools/list`, `tools/call`,
  `resources/list`, `resources/templates/list` and `resources/read`, takes
  `notifications/initialized` and every other notification unanswered, and
  answers any other method with JSON-RPC's *method not found*; `McpTools`
  builds a call's line from the options each command already declares;
  `McpResources` lists the scopes, gives the templates and reads one as
  `show` and `list`. `McpServerTest` scripts a session over in-memory
  streams against the test cluster's names.
- The templates follow the tree as built: a cluster, a node and the path
  beneath a node. The artifact segments of ADR-0027's amendment of
  2026-10-06 are decided and not built; the templates change when the tree
  does.
- An MCP client sees what an Observer sees and no more, until the second
  open question is answered.
