# ADR-0053: Every System Process Xmip owns says whose it is

- Status: Accepted
- Date: 2026-09-18
- Related: ADR-0011 (names), ADR-0014 (the operator surfaces; clause 8, the
  executable), ADR-0052 (clause 5, the executable), ADR-0028 (the
  Playground spawns nodes as System Processes), ADR-0025 (module loading),
  ADR-0045 (offline is the default)

## In brief

- Theme: Operating Xmip
- Subject: What a System Process Xmip owns is called, and what it says of
  itself
- Name: Every System Process Xmip owns says whose it is
- Order: 13
- Concepts: System Process names; xmip-; process declaration; purpose, test, runtime

**Every System Process and every service Xmip owns is named `xmip-<what>`,
and declares three things about itself: its name, its location and its
purpose, which is Test or Runtime. One line finds them all, and one line
stops them all: `Get-Process Xmip-* | Stop-Process -Force`.**

## Context

The owner, 2026-09-18, after an evening of locked build directories: *every
process, every service that Xmip owns should declare its name, location and
purpose. Test or Runtime. I want to be able to kill all processes by running
`Get-Process Xmip-* | Stop-Process -Force`.*

Xmip built six executables and one of them would have matched. The
Playground's were `roll` and `node`, and `node` was Node.js's name long
before it was this one's. The web monitor was `Xmip.Gui.Web`, the desktop
`Xmip.Operations`, the executable `xmip` with no dash, and only the language
server, `xmip-lsp`, fit. What that cost was paid the same day: a web host
started elevated locked the GUI's build output, `Get-XmipOperationWeb` could not see
it because an elevated process shows no path, `Stop-XmipOperationWeb` could not stop
it, and a landing waited on its owner finding the shell it came from. A
PowerShell session holding the prompt module did the same twice.

The rule already existed for everything else. A name that enters a shared
namespace carries the prefix, and a name inside the estate does not (the
owner, 2026-09-05: *there is a world outside of Xmip*). The operating
system's process list is a shared namespace. And the vocabulary already asks
it of the Xmip Host Service, whose *service name and description are
generated from configuration when it is registered, so an operator reading
the service list can tell what each one does* (`terminology.md`).

## Decision

### 1. The name is `xmip-<what>`

Every executable Xmip builds, and every service it registers, is named
`xmip-` and then what it is, lower case, words joined by dashes. No
exception: the executable is `xmip-cli`, by the owner's word the same day,
because a forgotten `--follow` session is exactly the process that holds a
lock, and a rule with one exception is a rule someone has to remember.

| was | is |
|---|---|
| `roll` | `xmip-playground-roll` |
| `node` | `xmip-playground-node` |
| `xmip` | `xmip-cli` |
| `Xmip.Gui.Web` | `xmip-gui-web` |
| `Xmip.Operations` | `xmip-operations` |
| `xmip-lsp` | `xmip-lsp` |

The Xmip Service and the Xmip Host Services, when they are built, are
`xmip-service` and `xmip-host-<name>`, the name generated from
configuration as the vocabulary already says. A project, a namespace and a
source file keep the names they have; this is the name the operating system
schedules.

### 2. The name vouches where the path cannot

Tooling that finds Xmip's processes asked each for its path and compared it
with the build output, and an elevated process shows no path to a session
that is not. Since nothing else is named `xmip-*`, the name vouches for a
process whose path cannot be read.

### 3. A process declares its name, its location and its purpose

Three things, said by the process itself and readable while it runs:

- **name** — what it is, the `xmip-<what>` above.
- **location** — where in Xmip it belongs: the scope it serves, such as
  `xmip:///C1` or `xmip:///C1/node/R1`, or the surface it reads where it
  serves none.
- **purpose** — `test` or `runtime`. The Playground and everything it spawns
  is test. A process is runtime unless what started it says test.

Built the same day. A process writes its declaration where it starts, to
one file named for it and its pid — `xmip-gui-web-4242.toml` — and takes it
away where it ends. The directory is the node's to say, in
`XMIP_PROCESS_DIRECTORY`; unset, it is `xmip/process` under the system's
temporary directory, the same for every process on the machine, so a reader
and a writer who were told nothing still meet. A process that is killed
cannot take its declaration away, so whoever lists them drops those whose
process is gone, and those whose pid now belongs to something not named
`xmip-*`.

One declaration, written twice in two languages because the estate has two:
`Declaration` in `xmip-core-node` for a Rust process, `ProcessDeclaration`
in `Xmip.Surface` for a .NET one, the same file in the same place. The
Playground's roll and nodes say test and the scope they are; the web host
says the surface it reads and test where `Start-XmipOperationWeb` started it over a
roll's file; the executable says the scope it was asked about and the
purpose its document states; the desktop says runtime.
`Get-XmipProcess` lists every `xmip-*` process with the three beside it,
and `Get-XmipProcess -Purpose Test | Stop-Process -Force` stops the tests
and leaves the product running. A process that declared nothing is still
listed, by its name: the name is the rule, the declaration the courtesy.
The language server is named as the rule says and does not declare yet; it
depends on the ABI alone, and the declaration is not the ABI's.

## Consequences

- ADR-0014 clause 8 and ADR-0052 clause 5 name the executable `xmip`; it is
  `xmip-cli`, and an operator types `xmip-cli health <scope>`. Both records
  are amended.
- `Get-XmipOperationWeb`, `Get-XmipTestStatus` and `Get-XmipTestNode` find processes
  by the new names, and see one started elevated.
- On Linux the kernel keeps fifteen characters of a process name, so
  `xmip-playground-roll` and `xmip-playground-node` both read
  `xmip-playground`; the prefix survives, which is what the one line needs.
- The deploy lists name repositories, not processes, and do not change.

## Alternatives considered

**Keep `xmip` for the executable and exempt it.** The command stays short.
Declined by the owner: the one line would miss a running `xmip ... --follow`,
and that is the process most likely to be forgotten.

**A registry of process ids instead of a name.** The Playground already
writes a record per roll. A record is lost where a process dies hard, and a
name cannot be; the record stays, as the declaration of clause 3, beside the
name and not in place of it.

## Provenance

The requirement, the one line and the executable's new name are the
owner's, 2026-09-18. The table, clause 2 and the shape of clause 3 are the
assistant's drafting of it.

## Amendment, 2026-09-19: the cluster is a process, and says so

The owner: *even clusters have to be spawned as processes during tests.*

A fourth name joins the table, `xmip-playground-cluster`, and a Playground
run is a tree of three declarations rather than two. The roll is the test,
the cluster is a process the roll spawns, and the nodes are processes the
cluster spawns; each declares its name, its location and purpose Test where
it starts, as clause 3 requires:

| process | location |
|---|---|
| `xmip-playground-roll` | `xmip:///<cluster>` |
| `xmip-playground-cluster` | `xmip:///<cluster>` |
| `xmip-playground-node` | `xmip:///<cluster>/node/<name>` |

The roll and its cluster share a location, because they are the test of that
cluster and the cluster itself; the name tells them apart, which is what
clause 1 is for. `Get-XmipProcess` shows all three, and
`Get-XmipProcess -Purpose Test | Stop-Process -Force` still stops them all.
The ordinary way to end a run is `Stop-XmipTest`, which ends the tree from
the leaves up so nothing is orphaned (ADR-0028, amendment 2026-09-19).
