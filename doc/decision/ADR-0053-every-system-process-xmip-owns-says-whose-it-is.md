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
stops them all: `Get-Process xmip-* | Stop-Process -Force`.**

## Context

The owner, 2026-09-18, after an evening of locked build directories: *every
process, every service that Xmip owns should declare its name, location and
purpose. Test or Runtime. I want to be able to kill all processes by running
`Get-Process Xmip-* | Stop-Process -Force`.*

The quote keeps the owner's own capital. Windows matches a process name
without regard to case, so `Xmip-*` finds them and nobody noticed for two
days — but the processes are named `xmip-*`, and on 2026-09-20 the owner
caught the estate's own instructions teaching the wrong spelling. They were
corrected; this line was not, because a quote is what was said and not what
is true. Where the two differ in this record, that is why.

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
  `xmip:///C1` or `xmip:///C1/node/alpha`, or the surface it reads where it
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

## Amendment, 2026-09-20: the name says which cluster and which node

The owner, reading `Get-Process Xmip-*` with two clusters rolling: *these
process names does not tell an operator or developer much. … Cluster, Node
and test suite shall be incorporated in the process name.* Eleven rows said
`xmip-playground-node` six times over, `xmip-playground-cluster` twice and
`xmip-playground-roll` twice, and nothing in the list said which cluster any
of them belonged to. The information existed — every one of them declares its
location under clause 3, and `Get-XmipProcess` printed `xmip:///W1/node/P1`
beside it — but `Get-Process`, Task Manager, Resource Monitor and every other
tool the operating system gives show the image name and nothing else.

### 4. A Playground process is named for its suite, its cluster and itself

`xmip-<suite>-<cluster>-<what>`, where `what` is `roll`, `cluster`, or
`node-<name>`:

| process | name | location |
|---|---|---|
| the roll | `xmip-playground-W1-roll` | `xmip:///W1` |
| its cluster | `xmip-playground-W1-cluster` | `xmip:///W1` |
| a node | `xmip-playground-W1-node-alpha` | `xmip:///W1/node/alpha` |

Clause 1 is untouched and is why this works: every one still begins `xmip-`,
so `Get-Process Xmip-* | Stop-Process -Force` still stops them all, and
`Get-Process xmip-playground-W1-*` is now one cluster's tree. The cluster
sits at a fixed column, which is what makes twenty rows readable at a glance;
the kind follows it, which is what tells the roll and its cluster apart where
they share a location.

The name a process was given before this stays its name where nobody named a
cluster: a roll started by hand with `cargo run --bin xmip-playground-roll`,
and the crate's own tests, are still `xmip-playground-roll`,
`xmip-playground-cluster` and `xmip-playground-node`.

**The kind is a marker the name carries, and no word is reserved.** The shape
first drafted here made the kind the *last* word — `xmip-playground-W1-R1` for
a node — and then had to forbid a node being called `roll` or `cluster`, or
ending in `-roll` or `-cluster`, so that `xmip-playground-W1-my-roll` could not
be read as W1's roll. The owner struck that the same day: *a node is a node and
can have one or more roles, roll is something different.* He had ruled hours
earlier that node names are the operator's and arbitrary (*Rn, Pn and Sn are
arbitrary node names*), and a reserved word contradicts it: the shape must
carry the distinction, not the operator. So a node's word is `node-<name>`.
`xmip-playground-W1-node-roll` is the node called `roll` and is nobody's roll;
`xmip-playground-W1-roll` is still W1's roll. A reader — and
`Get-XmipPlaygroundImageKind` — takes the marker first and the endings second,
which is what makes the two unambiguous.

A node's name is a file name, for the reason clause 5 gives, so it takes the
same shape a cluster's name takes — letters, digits and hyphens, starting with
a letter — and **that is the whole of the rule**. Anything else is REFUSED at
the door and nothing is spawned (ADR-0055); it is never quietly mangled into a
name that works.

The cost is paid where a level names its own nodes `node-01`: that node is
`xmip-playground-W1-node-node-01`. It is ugly, it is rare, and it is true,
which is worth more than a name an operator may not use. What the marker does
not settle is a *cluster* whose name ends in `-node`: its roll would read as a
node of a shorter cluster. No cluster is named that today, nothing is refused
for it, and the declaration of clause 3 says which it is; if it ever matters
the owner rules, and the answer is not a reserved word.

### 5. The name is a file, because a process cannot be renamed

On Windows a process's name is its **image file's** name, and a running
process cannot be renamed; on Linux the name follows the executable too. A
distinct name per instance is therefore a distinct file per instance. Each is
a **hard link** to the built binary in device-local space — `.local-work`,
which `CONTRIBUTING.md` reserves for what this machine needs to run Xmip —
and a copy only where a link cannot be made, on another volume or a file
system without them. Nothing is written into the repository, and the links go
when the roll ends: the roll takes what it can on its way out, `Stop-XmipTest`
takes the rest, and the next roll on the same cluster clears the directory
before it starts.

A link is not a micro-optimisation here. The node binary is twenty-one
megabytes and the brutal level brings forty nodes; copying would write eight
hundred megabytes for every roll, on every start.

### 6. The declaration is the name the process actually has

Clause 3 says a process declares its name. It now declares the name the
operating system lists it under, read from its own image rather than written
as a constant, so a declaration cannot drift from the process list — which is
what would make `Get-XmipProcess` lie. `Get-XmipPlaygroundProcess` judges a
process by its declaration first and by its name second (2026-09-19), and the
per-instance names go through it: it is asked for a **kind** — Roll, Cluster
or Node — rather than for one of three fixed names, and the kind is read off
the name the same way on both paths. A roll stays findable and stoppable by
`Get-XmipTestStatus`, `Get-XmipTestNode` and `Stop-XmipTest`.

### What the other processes do, and why

- `xmip-gui-web` keeps its name. One web host now serves every cluster at
  once (ADR-0052, amendment 2026-09-20), so there is no one cluster to put in
  its name, and its declared location already says which surface it reads.
  Naming it for a cluster would be the lie this amendment exists to remove.
- `xmip-cli` keeps its name. An invocation is short-lived and answers about
  one scope, which it declares; it is not a process an operator finds in a
  list and wonders about. `--snapshot <path>` already says which cluster it
  read.
- `xmip-lsp`, `xmip-operations`, `xmip-service` and `xmip-host-<name>` are
  unchanged; none of them is one of many alike.

### What follows from it

- On Linux the kernel keeps fifteen characters of a process name, so every
  one of these still reads `xmip-playground` in `ps -o comm`. The prefix
  survives, which is what the one line needs; the whole name is in
  `/proc/<pid>/exe`, in `ps -o args`, and to `pgrep -f`. The consequence
  ADR-0053 already recorded is widened, not introduced, and an operator on
  Linux reads the cluster from `Get-XmipProcess` as before.
- `Get-XmipTestNode`'s walk from a node up to its roll asks which **kind** a
  parent is rather than comparing its whole name, since the name now carries
  a cluster.
- The image directory is the Playground's alone, so a process running out of
  it is the Playground's without further proof — which is what keeps the
  rebuilt-binary warning of 2026-09-19 from firing on every ordinary run.
- **Every surface, and the one that owes nothing** (ADR-0014, amendment
  2026-08-30). A process name reaches exactly one surface: PowerShell's
  `Get-XmipProcess`, whose table widened for it, with `Get-XmipTestStatus`
  and `Get-XmipTestNode` finding a run's tree by kind. `xmip-cli`, the web
  GUI, the desktop and the prompt show scopes, health and rates and have
  never shown a process name, so none of them changes; a scope like
  `xmip:///W1/node/alpha` already said which cluster and which node, and this
  amendment exists because the operating system's own list did not.
- Where a session's build directory is held open by another session's roll,
  `CARGO_TARGET_DIR` moves both the build and what the cmdlets link and run:
  `Get-XmipPlaygroundLayout` asks cargo rather than assuming `target/debug`.
  That is the *target choice* `CONTRIBUTING.md` reserves `.local-work` for,
  and it is how a second session builds at all while a roll is up.

The requirement and the shape are the owner's, 2026-09-20, as is striking the
reserved words the assistant had drafted under it the same day; the node
marker that replaced them, the link and clause 6 are the assistant's drafting.

## Amendment, 2026-09-25: a roll's processes are the ones declared in its cluster

On 2026-09-25 a brutal roll's cluster restarted its nodes faster than they
could be listed (ADR-0052, amendment of the same date): each node read by
`Get-XmipTestNode` was already gone, or not yet a child, when its parent was
asked, so `Get-XmipTestStatus` said *Nodes: none* while seventeen ran, and
`Stop-XmipTest`, which asked the nodes beneath the roll to leave, asked none
and ended their cluster under them. The tree is a fact of one moment; the
location a process declared is not.

- `Get-XmipTestNode` carries each node's declared `Location`, and a node is
  its roll's by the tree **or** by a location inside the roll's cluster
  (`Test-XmipTestNodeOfRoll`), for the status and the stop alike.
- After the roll's cluster process, `Stop-XmipTest` ends every live process
  that declared its location as the cluster's root or inside it
  (`Stop-XmipTestCluster`, `Test-XmipClusterLocation`): `xmip:///C1` and
  `xmip:///C1/node/node-01` are C1's, `xmip:///C10/...` is not. A declaration
  is compared as its segments' prefix and never read for meaning.
- A declaration file whose process ended between the listing and the read
  is a process gone, not an error (`Read-XmipProcessDeclaration`).

`test/XmipTest.Test.ps1` holds it: a stopped roll ends every process
declared in its cluster and nothing declared in another. The owner's report
is the lead's, 2026-09-25; the rule is the assistant's drafting.
