# ADR-0057: A vtable is a promise; only a loader is a saving

- Status: Accepted
- Accepted: 2026-09-20, the owner, on being shown what each record named
  as his to strike. Nothing was struck.
- Date: 2026-09-19
- Related: ADR-0012 (the module boundary — this record extends it and
  reopens none of it), ADR-0025 (when a Module loads), ADR-0027 (the
  operator boundary, which amended ADR-0012), ADR-0044 (a technology shares
  through its capability), ADR-0049 (a host crate keeps its source in
  `.src`), ADR-0042 (a contract holds well-formedness always), ADR-0019
  (identity, parties and direction), ADR-0050 (an identity technology is one
  mechanism at one gate)

## In brief

- Theme: Modules and the boundary
- Subject: What a trait table buys, and what only a loader buys
- Name: A vtable is a promise; only a loader is a saving
- Order: 10
- Concepts: Wave two; trait table; the loader; vtable shim; ABI-friendly trait

**A trait table buys a versioned, language-neutral promise, and buys nothing
back from the build. The day's lost work goes only when a technology stops
being a Cargo dependency and becomes an artifact the host opens at run
time — and the estate has no loader at all. Buy the table first, because
sixteen traits have none and a loader cannot load what has no table; buy the
loader second, because that is where the saving is. `authenticate` is wave
two, at trait version 1.0, and nothing follows it until a loader has loaded
one.**

## Context

The owner, 2026-09-19: *If the ABI were more solid, you do not have to work
so much.*

ADR-0012 predicted the cost he felt. Its Context: *One global version cannot
carry seventeen contracts… any change to any trait invalidates every module
in the system — which makes independent runtime upgrade of a sub-module
impossible, and that is the property the repository and sub-module split
exists to provide.* Its Decision clause 6 answered it: *Each core module
versions its own trait independently.* The record is Accepted and its Status
says *Implementation follows in separate reviewed changes*.

What was implemented, read today:

- `module/foundation/abi/include/xmip_module.h`, 464 lines, defines **four**
  trait tables — `XmipTransportVtable`, `XmipMessageVtable`,
  `XmipPathVtable`, `XmipContractVtable` (header sections 9 to 12). The
  specification beside it, `module/foundation/abi/doc/specification.md`,
  457 lines, calls them *creation wave one* and says the other thirteen are
  *deliberately unspecified*.
- The Rust mirror, `module/foundation/abi/.src/ffi.rs`, 338 lines, holds
  **two** of the four: `TransportVtable` and `ContractVtable`. There is no
  `MessageVtable` and no `PathVtable` in it. Counted by searching the file
  for `pub struct …Vtable`. That file's own doc comment says *where the two
  ever disagree, the header is right and this is a defect*.
- Seven contract technologies already speak the table: `contract/c`,
  `cpp`, `go`, `java`, `python`, `dotnet` and `rust` — each built as a
  loadable library, each driven through `contract/probe/probe.c` by its own
  `verify.ps1`. `contract/c/src/contract.c` fills a real
  `XmipContractVtable`. `contract/rust`'s README says it plainly: *a
  loadable module over the ABI rather than a crate the runtime links.*

And what was not:

- **Nothing in the estate opens a module.** `libloading` appears in exactly
  one `Cargo.toml` of the 240 that carry Xmip git dependencies —
  `module/operation/gui/vscode` — and it loads the runtime's own library
  through `xmip_operate.h`, the boundary that faces the other way
  (ADR-0027). `module/platform/runtime`'s `dynamic-loading` feature contains
  `verify_dynamic_module`, which checks a descriptor and returns a struct;
  it never opens a library and never looks up a symbol.
- **Nothing links a technology into a node.** `module/platform/runtime`
  depends on 16 Xmip crates and not one of them is a technology. The `xmip`
  assembly crate at the repository root names 33, all of them Foundation,
  Capabilities, Platform or Operations. The one place technologies are
  linked is `test/playground`, which names 123 distinct Xmip crates, 111 of
  them with a fourth name part — a technology under ADR-0011.

The measured coupling, counted on 2026-09-19 by searching every `Cargo.toml`
outside `target/` for `git = "https://github.com/IlleNilsson/`: **843
dependency edges across 240 manifests, naming 150 distinct repositories,
every one of them on `branch = "main"`** (ADR-0005). That is the shape that
makes a rename take four landings.

## Decision

### 1. The table and the loader are two purchases, and they are named apart

Extending the ABI is two separate things and the estate has been saying one
word for both.

**A trait table** is a published, versioned, language-neutral promise: a
`repr(C)` table, a `trait_major`/`trait_minor` pair, and a compatibility
rule. It lets a mechanism be authored in another language. It removes
**nothing** from the build, because a Rust technology that implements the
Rust trait keeps its `Cargo.toml` line exactly as it is.

**A loader** is the host opening a shared library, looking up
`xmip_create_module_v1`, calling it, checking the descriptor and selecting
the table by `descriptor.module`. That is what turns a technology from a
Cargo dependency into an artifact — and it is the only one of the two that
takes an edge out of the 843.

The estate buys the table first because sixteen traits have none and a
loader cannot load what has no table. It buys the loader second because that
is where the owner's lost day is.

### 2. Honest about what clause 1 means for `authenticate`

Giving `authenticate` a vtable does **not** remove
`authenticate = { git = …, branch = "main" }` from
`module/capability/authenticate/kerberos/Cargo.toml`. That line is there
because the crate implements the Rust `Authenticator` trait and uses
`Presented`, `Mechanism`, `Verified` and `AuthenticateError`. A C table
published beside that trait leaves the line where it is. The line goes when
the technology exports `xmip_create_module_v1` instead of implementing a
Rust trait — and then only if something loads it.

### 3. `authenticate` is wave two, and it is alone

Eighteen technologies (counted as the directories directly under
`module/capability/authenticate` that hold a `Cargo.toml`: `api-key`,
`basic`, `bearer`, `certificate`, `digest`, `jwt`, `kerberos`, `ldap`,
`mutual-tls`, `ntlm`, `oauth2`, `oidc`, `pam`, `password`, `saml`, `scram`,
`ssh-key`, `windows`; `doc` and `target` are not technologies).

It is chosen for four reasons, in order:

1. **Its types are already ABI-friendly.** `Presented` is a mechanism, a
   string value, a three-valued `Established`, and two lists of string
   pairs. `Verified` is a three-variant C-like enum. `Mechanism` is a name
   plus three small enums. Nothing in it is a stream, a parsed tree, a trait
   object, a lifetime or a closure. It is the only capability of real size
   whose whole input and output is short strings.
2. **The trait is three methods**, one with a default:
   `mechanism()`, `verify()`, `conclude()`.
3. **A third party has a reason to write one.** `mechanism.rs` in
   `xmip-core` names the case itself, in a comment about a provider adding
   `xmip-<provider>-authenticate-scim`. A bank's HSM and a customer's SCIM
   directory are the plausible first non-Xmip modules, and neither author
   wants to write Rust.
4. **The gate is small and well fenced.** ADR-0019 clause 2 and ADR-0050
   bound it: one mechanism, one gate, a closed declared set.

`identify` has one more technology (19) and is not chosen: its
`StreamArrival<'a>` carries a lifetime and its message gate needs a parsed
`Message` across the boundary, which is the `XmipMessageVtable` problem
again and not a new one.

### 4. It starts at trait version 1.0 and versions alone

`trait_major = 1`, `trait_minor = 0`, under ADR-0012 clause 6. The four
wave-one tables are at 1.0 today — `examples/conforming.rs` and the
`dynamic-loading` tests both write 1 and 0 — and `authenticate` starting at
1.0 says nothing about them and is constrained by none of them. That is the
whole point of clause 6.

### 5. What ADR-0012 and ADR-0027 already settled is not reopened

Cited so this record extends rather than contradicts:

- The descriptor layout — `abi_version`, `provider`, `module`, `standard`,
  `trait_*`, `module_*` (ADR-0012, *The descriptor*; header section 4).
- The `abi_version` handshake: a module that cannot support the host's
  version returns `XMIP_E_UNSUPPORTED` from the entrypoint and leaves `*out`
  untouched (header section 7).
- The compatibility rule: `abi_version` equal, `module` equal,
  `trait_major` equal, `trait_minor` less than or equal (ADR-0012,
  *Compatibility*). Capability negotiation was considered there and
  rejected; this record does not revive it.
- Unwinding never crosses (clause 8). `dyn Trait` never crosses (clause 4).
  No Rust types in the interface.
- No license exception for the boundary (clause 9).
- ADR-0027's amendments to ADR-0012 stand: a second header versioned apart,
  and `XmipNode`/`XmipNodeKind` renamed to `XmipValue`/`XmipValueKind`.

### 6. The shim is Xmip's, and `dyn Trait` stops at it

`authenticate::authenticate()` takes `&[&dyn Authenticator]`. A loaded
module reaches it through an adapter on the Xmip side — a type holding a
`*const XmipAuthenticateVtable` and implementing `Authenticator`. The trait
object exists only inside Xmip and never approaches the boundary, which is
ADR-0012 clause 4 satisfied rather than bent.

### 7. What the other sixteen would cost

The estate has 19 capability directories plus `message` under Foundation,
so there are 20 candidate traits and not ADR-0012's seventeen. Four are
specified. Sixteen are not, and three of those sixteen have no Rust trait to
specify. Technology counts were taken on 2026-09-19 by counting the
directories directly under each capability that hold a `Cargo.toml`; method
counts by reading each `.src/lib.rs` or `src/lib.rs`. `resilience` is
counted as a capability because it moved from `module/platform` to
`module/capability` on 2026-09-19; that move was in the working tree and not
yet landed when this was written, so a committed tree may still read 18.

| capability | tech | trait and methods | types |
| --- | --- | --- | --- |
| `authenticate` | 18 | `Authenticator` 3 | plain data — **the slice** |
| `identify` | 19 | `TransportIdentifier` 2, `MessageIdentifier` 2 | a lifetime; a `Message` |
| `authorize` | 14 | `Authorizer` 3 | plain data; `Option<Decision>` |
| `route` | 8 | `Source` 2 | needs a `Message` handle |
| `resilience` | 6 | `Guard` 3 | plain data; the host side is generic |
| `logic` | 4 | `Logic` 5 | `Arrival<'a>`; rich `Outcome`/`Fault` |
| `process` | 0 | `XmipProcess` 4, `ProcessRegistry` 1 | `Message` in and out |
| `transform` | 0 | `Transformer` 4, `TransformRegistry` 1 | `Message` out; contract descriptors |
| `receive` | 0 | `ReceiveTransport` 2, `ReceivePublisher` 1 | duplicates the transport table |
| `send` | 0 | `SendTransport` 2 | duplicates the transport table |
| `prepare` | 0 | `PrepareStep` 2 | `Stream` in, `Stream` out |
| `retain` | 0 | `RetentionPolicy` 1 | plain data — and no technology |
| `demote` | 0 | `ArtifactTarget` 1 | `&mut dyn StructureWriter` at its call site |
| `assign` | 0 | none | free functions over `MessageContext` |
| `promote` | 0 | none | free functions over `MessageContext` |
| `migrate` | 0 | none | a six-line stub |

**The hard ones, and why.** `identify`, `route`, `process` and `transform`
all need a parsed `Message` to cross, which is the `XmipMessageVtable`
problem — and that table exists in the header and is *not* in the Rust
mirror, so it is unproven in both directions. `logic` carries a borrowed
`Arrival<'a>` and a `Fault` with structure, and it has four technologies to
pay for it. `demote` reaches the payload through `&mut dyn StructureWriter`,
a trait object at the call site, so a table for it forces the structure
writer across the boundary first. `receive` and `send` are the awkward
pair: they hold traits and zero technologies, while `transport` is
direction-neutral under ADR-0010 and carries 84 — a table for each of the
three would say the same thing three times. `assign`, `promote` and
`migrate` have nothing to specify, which is open problem 4.

**The runner-up is `resilience`.** `Guard` is three methods over plain data —
a try number in, an `Attempt` in, a `Decision` out — and ADR-0048 already
fixed its shape, so the table would be transcription rather than design. It
loses to `authenticate` on size, six technologies against eighteen, and on
demand: nobody outside Xmip wants to write a retry policy, and several
people want to write a mechanism. Note that only its module-side trait is
ABI-friendly; `ResilienceExecutor::execute<T, E, F>` is generic over a
closure, which specification section 12 forbids outright, so that half stays
inside Xmip whatever happens.

### 8. The order of work, and the risk in each step

1. **Close the mirror gap.** `ffi.rs` gains `MessageVtable` and
   `PathVtable`, so all four wave-one tables exist on both sides. Low risk,
   no new promise made, and it is a defect by that file's own words.
2. **Write the loader, against a table that already exists.** Open a
   library, resolve `xmip_create_module_v1`, call it with an `XmipHost`,
   run `validate_module_abi`, select the table by `descriptor.module`, hold
   the instance, call `destroy` on the way down. Prove it against
   `contract/c` and `contract/rust`, which already build and already pass a
   probe. **This is the risky step** and it is deliberately taken against
   wave one rather than against a table written the same week: `unsafe`
   crosses here for the first time in a production crate, and the
   conformance suite that would check it *does not exist* (specification
   section 11 says so).
3. **Then, and only then, `XmipAuthenticateVtable`.** Header section 13,
   specification wave two, Rust mirror, and one technology ported as proof.
4. **Then measure.** If landing that one technology no longer requires
   landing `xmip-core-authenticate` first, the saving is real and the next
   capability is worth arguing about. If it does, this record was wrong and
   should be superseded rather than extended.

### 9. What would not be done

- **No table for the other fifteen.** One at a time, each written with an
  implementation in front of it. ADR-0012's reasoning stands: *a trait table
  designed without an implementation in front of it is a guess, and a guess
  published as `v1` becomes a permanent compatibility promise.*
- **No change to the four wave-one tables.** They are published.
- **No second global version.** Clause 6 of ADR-0012 already answered it.
- **No async, no generics, no allocator in `XmipHost`** — specification
  section 12, unchanged.
- **No rewrite of the Rust traits into the vtable's shape.** The Rust side
  stays ergonomic; the shim absorbs the difference.
- **No removal of a single git dependency in this record.** That is what
  step 4 measures, not what this record claims.

## Consequences

- **The estate learns whether the boundary works, on the cheapest case it
  has.** Seven contract technologies in seven languages build and pass a
  probe today; not one of them has ever been opened by Xmip. Step 2 is the
  first time the two halves meet.
- **`ffi.rs` mirroring two of four tables is a defect on the record.** It
  was invisible because nothing built against the missing two.
- **Two places where the Rust side is behind its own specification** are
  named rather than left to be found. `module/foundation/stream` holds a
  `Stream` as `Arc<[u8]>` — the whole payload resident — while
  specification section 8 says *an Xmip stream may be larger than memory* and
  *never crosses the boundary as a buffer*. `Transport::receive()` in
  `module/capability/transport/.src/protocol.rs` returns
  `Result<Vec<Arrived>>` with `Arrived { origin_uri, bytes: Vec<u8> }`,
  materialized, while `XmipTransportVtable` streams through `XmipReader`.
  Neither contradicts a decision; both mean a vtable is not a mechanical
  wrap of the trait beside it, for the one capability where both exist.
- **ADR-0025's delay-load becomes real or stays theatre.** Clause 3 says a
  delayed Module is loaded on the first call that needs it. Until step 2
  there is nothing to delay.
- **A node still cannot use a technology.** The runtime links none and
  loads none; only `test/playground` names them. That is the plainest
  statement of why this work matters, and it is not a new fact — it is what
  the queue's item 1, *run a node for real*, has been waiting on.
- **For the owner to rule on.** Four things this record found and does not
  decide: (a) `receive` and `send` hold traits with zero technologies beside
  a direction-neutral `transport` with 84 — one of the three should not get
  a table; (b) ADR-0012's *seventeen traits* is now nineteen candidates, so
  its *other thirteen* should be read as a count of its day, not a list;
  (c) whether the conformance suite is a precondition of step 2 or may
  follow it; (d) whether `packaging` (ADR-0015) must cover native libraries
  per platform and architecture before any module is loaded — ADR-0027's
  consequences already say it does not today.

## Alternatives considered

**Write the loader first and skip the table.** Tempting: the saving is in
the loader, and four tables already exist. Rejected as a whole because it
buys the saving for four capabilities and nothing for the other sixteen —
but it is *adopted for step 2*, which is exactly this alternative applied to
wave one, where the table is already paid for.

**Give all fifteen a table in one pass.** It would end the question in one
change and it would publish fifteen permanent compatibility promises written
without an implementation in front of any of them. ADR-0012 rejected this by
name, and nothing since has weakened its reasoning.

**Drop the C ABI and accept the Rust coupling.** Honest, and it costs the
platform's stated position: `artifact-model.md` lists Rust, C, C++, COM,
.NET, Java, PowerShell and native binaries as module technologies, and seven
contract technologies in six non-Rust languages already exist. It also gives
up *their licence, their support* (ADR-0012 clause 9), which is a commercial
position and not an engineering one.

**Replace `branch = "main"` with version pins to cut the rebuild.** It
addresses the symptom the owner felt and none of the cause; ADR-0005 chose
`main` deliberately for the pre-alpha, and pinning 843 edges by hand is a
worse afternoon than the one being avoided. It is also orthogonal: a pinned
Cargo dependency is still a Cargo dependency.

**Start with `identify` instead, for its 19 technologies.** One technology
more than `authenticate`, and it needs a `Message` across the boundary for
its second gate. The extra technology does not pay for the extra problem.

## Provenance

**The owner's**, 2026-09-19: *If the ABI were more solid, you do not have to
work so much.* That sentence is the whole reason for this record, and the
observation behind it — that a change to a capability cannot be verified
without patching a git dependency to a local path, and that one rename took
four landings — is his, from the same day's work.

**The assistant's**, everything else: the nine clauses, the split between a
table and a loader in clause 1, the choice of `authenticate` in clause 3,
the cost table in clause 7, the order in clause 8 and the four questions at
the end of Consequences.

**Verified rather than assumed.** Every count in this record was taken from
the tree on 2026-09-19 and the method is stated beside it. The vtable
inventory is from reading `xmip_module.h` and `.src/ffi.rs` in full; the
technology counts from counting directories holding a `Cargo.toml`; the
dependency figures from searching every `Cargo.toml` outside `target/`.

**Unverified, and marked so.** The `cargo --config 'patch…'` workaround and
the four-landing rename are the owner's report of the day's work; neither
appears anywhere in the repository, so this record cites them as his
observation and not as something it checked. Whether a loaded
`authenticate` module could satisfy `Mechanism::declare` — which states
class, layer and assurance and is deliberately unreachable from TOML — is
unresolved here: the table would have to carry all four fields, and the
assistant has not designed that and does not claim it is free.

This record is Proposed. It extends ADR-0012 and contradicts no clause of
it; where it found the implementation behind the specification, it says so
in Consequences rather than quietly changing either.

## Amendment, 2026-09-19: step 2 is built, and it has opened two modules

Clause 8 step 2 is done, in the order clause 8 recommends and against wave
one rather than against a table written the same week. Step 1 — the mirror
gap in `ffi.rs` — was **not** needed for it and was not done: the contract
table was already mirrored, and `MessageVtable` and `PathVtable` remain
absent.

**What was built.** Three files in `xmip-core-runtime`, the host:

- `src/compatibility.rs` — ADR-0012's *Compatibility* rule as
  `accepts(descriptor, expectation)`. `abi::validate_module_abi` answers the
  first line (`abi_version`); the other three need a second party, the
  capability doing the loading, which no descriptor can supply by itself.
  Not feature-gated, so the estate's own gate compiles and runs it.
- `src/loaded_module.rs` — the load. `LoadLibraryExW` with
  `LOAD_WITH_ALTERED_SEARCH_PATH` on Windows and `dlopen(RTLD_LOCAL)`
  elsewhere, as specification section 3 requires and as `libloading`'s
  portable constructor does **not** do on Windows; resolve
  `xmip_create_module_v1`; call it with an `XmipHost` whose three callbacks
  are real functions; copy the descriptor out; judge it; hold the library and
  the instance; `destroy` then unload, in that order, including on the
  refusal path.
- `src/loaded_contract.rs` — the contract table selected by
  `descriptor.module`, and `configure`, `start`, `bind`, `validate`,
  `implies`, `release`, `stop` driven through it. A byte range reaches the
  module as an `XmipReader` the host fills; diagnostics are copied before any
  further call, because the header lends them only until the next one.

Both loading files are behind the `dynamic-loading` feature, which existed
for this and had never held a loader.

**What it opened.** `module/capability/contract/rust`'s
`xmip_core_contract_rust.dll` and `module/capability/contract/c`'s
`xmip_core_contract_c.dll`, both already built in the estate, both driven
through the same code with no branch on language — a byte range validated,
`implies("descriptor")` answering `any`, `implies` on a key the standard
does not determine answering `NOT_FOUND`. That is the sentence in
Consequences — *not one of them has ever been opened by Xmip* — no longer
true. The C one is the load-bearing case: the host cannot tell what it
loaded, and now that is demonstrated rather than asserted.

**What the descriptor check enforces**, in ADR-0012's own order:
`abi_version` equal to the host's, `module` equal to the loading capability,
`trait_major` equal, `trait_minor` less than or equal. Every refusal names
the field and both values, and a refused module is destroyed and unloaded
rather than kept:

```text
xmip-core-contract-rust 0.1.0 (abi 1, trait 1.0) answers the 'contract'
trait and 'transport' is loading it: descriptor.module must equal the
loading capability
```

The table's own `XmipVtableHeader` is checked against the descriptor as
well. A module whose descriptor and table disagree about their trait version
is refused; the header makes both statements and nothing had ever compared
them.

**Where `unsafe` lives, and how much.** Eighteen blocks, in two files, and
nowhere else in the crate: eight in `src/loaded_module.rs` — of which two are
the Windows and non-Windows arms of the same function, so seventeen compile
on any one platform — and ten in `src/loaded_contract.rs`. Each carries a
comment naming the pointer's origin, its lifetime and who frees it. Beside
them are four `unsafe extern "C" fn` definitions, which are what the host
*hands to* a module — three host callbacks and one stream reader — and
dereference nothing between them but the reader's own context.
`unsafe_code` stays `deny` and those two files
allow it at the top with their reason, which is the pattern `operate.rs` and
`start.rs` already established for the boundary facing the other way
(ADR-0027). `compatibility.rs` has none, deliberately: the rule an operator
argues with should be readable without reading an `unsafe` block.

**The runtime is the right home** because the host is what loads. The
alternative was `xmip-core-abi`, which already holds the header, the
descriptor and the .NET probe — but ADR-0012 clause 2 makes that crate a
*convenience for module authors*, and a module author does not load modules.
A loader in the binding crate would also be a loader every module that used
the binding linked.

**Two corrections to this record's own Context.** Both were written from a
search of Rust and both are wrong for the same reason.

1. *Nothing in the estate opens a module* is false. `xmip-core-abi`'s
   `dotnet/Xmip.Abi/Module/ModuleProbe.cs` opens a library with
   `NativeLibrary.Load`, resolves the entrypoint, calls it with a real
   `XmipHost` including an `UnmanagedCallersOnly` log callback, reads the
   descriptor and destroys the instance. `xmip probe` in `xmip-core-cli` and
   `Get-XmipModuleDescriptor` in `xmip-core-powershell` both drive it. What
   was true, and is what the record meant: **nothing in Rust** opened a
   module, the runtime opened nothing, and nothing anywhere selected a trait
   table or called a trait function — the .NET probe reads the descriptor and
   stops. That last part is still the gap this amendment closes.
2. The `libloading` count stands, but its conclusion did not: a loader does
   not need `libloading`, and the .NET one uses the platform's own loader.

**What ADR-0012 and the specification disagree about, unresolved.**
ADR-0012's *Compatibility* says `trait_minor` **is less than or equal to**
the host's. `doc/specification.md` section 2 says *a module may be newer in
`trait_minor` than the host* and that the host may call any function the
module declares. Those are opposite rules for the same field. The code
implements ADR-0012's, because ADR-0012 is the decision and the
specification says the header wins over it only on the header's own
statements — and the header states no rule here, only the fields. **This is
for the owner to settle**, and it decides whether a node running an older
Xmip may load a newer module.

**What is still not done**, plainly:

- **Nothing calls this.** `host::dynamic::verify_dynamic_module` checks a
  request an operator composed; `LoadedModule::open` reads what a module
  actually filled; nothing joins them, and no node configuration names a
  library path. A node still cannot use a technology — the Consequences
  section's last bullet is unchanged.
- **Only `contract`.** `transport`, `message` and `path` have tables in the
  header and no host side here. `message` and `path` are still missing from
  `ffi.rs` entirely, which is step 1.
- **No gate runs the proof.** `Test-XmipModule` runs `cargo test` on the
  default feature set and then *builds* the declared features, so the estate
  compiles the loader and never runs its tests. Making them run is one of two
  choices — `dynamic-loading` becomes a default feature, or the gate tests
  features as well as building them — and both change how the estate lands
  code, so neither was taken here.
- **The conformance suite still does not exist** (specification section 11).
  This loader exercises rules 1, 4, 5 and 7 against two modules and proves
  nothing about the other three.
- **The host table is a stub in one respect**: `log` discards. A module's log
  lines should reach `xmip-core-observe` and do not.
- **Unloading is not proven safe in general.** It is sound for what this code
  does — one instance, every string copied at the call it arrived in, no
  thread started — and specification section 3's four conditions are not
  *checked*, they are *satisfied by construction*. A module that starts a
  thread would break that, and nothing here would notice.
