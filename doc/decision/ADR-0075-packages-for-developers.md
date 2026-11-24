# ADR-0075: Packages for developers

- Status: Accepted
- Accepted: 2026-11-24, the owner: *Go ahead*
- Date: 2026-11-24
- Related: ADR-0011 (module naming), ADR-0012 (the module boundary),
  ADR-0014 (the operator surfaces, the operate listener over the estate's
  HTTP/2), ADR-0030 (prefix external names), ADR-0061 (a provider builds
  against the capabilities; its decision 5, a registry, left open), ADR-0063
  (Xmip encrypts its traffic), ADR-0064 (developers design in VS Code),
  ADR-0066 (compiled units), ADR-0067 (a node has one address), ADR-0074
  (the runtime stays in Rust), ADR-0023 (the license; amended 2026-11-24),
  open problem 30 (HTTP/3)

## In brief

- Theme: Modules and the boundary
- Subject: What an external developer installs to extend Xmip, test with it and reach it, and from where
- Name: Packages for developers
- Order: 12
- Concepts: package; NuGet; dotnet new template; NativeAOT; Xmip.Module; Xmip.Templates; registry; operator API; Apache-2.0

**Four NuGet packages, in this order: `Xmip.Module`, with which a developer
writes every kind of extension Xmip has a seam for, and `Xmip.Templates`,
`dotnet new xmip-module`, first; `Xmip.Testing` second; `Xmip.Client`
third. Beside them the PowerShell Gallery's `Xmip` module, the VS Code
extension on both extension registries, `xmip-module` on crates.io for Rust
module authors, and the C header and libraries as release downloads. Code on
the installation's machine may use the C ABI; code on any other machine
reaches Xmip only over its operator API on HTTP/2. What a developer's code
links or compiles into itself is Apache-2.0, so a module stays its author's;
the rest of Xmip stays AGPL-3.0-or-later. Every name is reserved before
anything is published. Module and Templates are built; nothing is
published.**

## Context

The owner, 2026-11-24: *So what nuget or other packages do you recommend to
external developers?* Shown the recommendation this record holds: *Go
ahead*. Then, of how a package reaches Xmip: *The extensions, nuget has to
operate over the http api unless the foreign code is on the same machine,
then the ABI can be used*; and of which HTTP: *Preferably HTTP/2, the latest
of everything. We are in developing mode.*

Until this record a developer outside the estate had the C header, the Rust
crates at `branch = "main"` (ADR-0061 decision 5 left a registry open) and
nothing in .NET: `Xmip.Abi` is the surfaces' binding inside the estate.

## Decision

1. **NuGet, four packages, built in this order.**
   - `Xmip.Module`: extend Xmip from .NET. Every unit capability — prepare,
     promote, demote, transform, validate, work-process — and later the
     transports, the archive targets, the warehouse connectors and Quests:
     one package for every extension seam. A developer writes a unit in C#
     and publishes it with NativeAOT as a native library a node opens
     through the C ABI exactly as it opens a Rust module.
   - `Xmip.Templates`: `dotnet new xmip-module`, a Module with one unit and
     its test.
   - `Xmip.Testing`, second: test a unit or a flow in a developer's own
     tests, as BizUnit and MUnit do for BizTalk and MuleSoft.
   - `Xmip.Client`, third: Events, Archive, Reports and Operate behind one
     connection and one sign-in.

   `Xmip.Module` and `Xmip.Templates` are built (clause 5); the other two
   wait their turn.
2. **Other channels.** The PowerShell Gallery's `Xmip` module; the VS Code
   extension on the VS Code Marketplace and Open VSX under an Xmip publisher,
   where its `package.json` names the owner's own today; `xmip-module` on
   crates.io for a Rust module author; the C header and the libraries as
   release downloads. Not now: Maven (later, for MuleSoft's developers),
   Python (none, the owner's standing rule), npm (TypeScript stays in the VS
   Code extension).
3. **Where the foreign code runs decides how it reaches Xmip.** Code on the
   installation's own machine may call the C ABI: a unit `Xmip.Module`
   builds runs inside the node's process, on its machine by definition, so
   it is a library over `xmip_module.h`. Code on any other machine reaches
   Xmip only over its operator API — a node's operate listener, gRPC on the
   estate's own HTTP/2 (`net::http2`), JSON messages, inside Xmip's mutual
   TLS at the node's operate address (ADR-0014, amendments 2026-10-12 and
   2026-10-13; ADR-0063; ADR-0067) — and needs no native library there. A
   package speaks HTTP/2 to it and asks for HTTP/2 or higher, so it takes
   HTTP/3 by itself once Xmip serves it (open problem 30: declared, not
   built). `Xmip.Client` is over the operator API by default and over the C
   ABI only where it runs on the installation's machine; so is `Xmip.Testing`
   where it reaches a running installation, and the VS Code extension where
   the installation is on another machine.
4. **Names are reserved before anything is published**: the `Xmip.` prefix
   on nuget.org, `Xmip` on the PowerShell Gallery, the Xmip publisher on both
   extension registries and `xmip-module` on crates.io — the owner's to
   request. Every package ID carries the prefix: it lives in a namespace
   shared with the world (ADR-0030). This settles ADR-0061's open decision 5
   for these packages; the SDK's simulators are not among them.
5. **Built, 2026-11-24.**
   - **A Promote unit's table**, `xmip_module.h` section 14, trait 1.0, the
     first table of a unit beside the Work Process unit's (section 13), as
     section 13 is shaped: a library holds one unit, its descriptor's module
     `promote` and its standard the unit's name; `open` once per step entry
     with the stage word and the entry's settings, read through the unit's
     declaration with every default filled in, as one JSON object — the
     transfer form — and `promote` per Message, the content through an
     `XmipReader`, each value to the host's sink as its kind and bytes. The
     Rust mirror is `abi::ffi`; the runtime's loader is
     `ffi/loaded_promotion.rs`, the lifecycle every table begins with moved
     to `ffi/lifecycle.rs` and shared with the contract's. A node runs no
     step entry yet (`configure::step::unrun`).
   - **`Xmip.Module`**, beside `Xmip.Abi` in `xmip-core-abi`
     (`dotnet/Xmip.Module`): the module side of the header, as the abi crate
     is for Rust (ADR-0012 clause 2). The header's C# shapes are `Xmip.Abi`'s,
     once, and its assembly travels inside the package. It exports
     `xmip_create_module_v1` with `UnmanagedCallersOnly`, from its own
     assembly into the module's library (NativeAOT's
     `UnmanagedEntryPointsAssembly`); a unit is a class, `PromoteUnit`, that
     declares its name and settings and exports itself with
     `Export.Unit` from a `[ModuleInitializer]`; nothing crosses unwound, a
     refusal answered as `CONTRACT` or `MALFORMED` with why. Its build
     writes the module's `[[modules]]` entry, `<Name>.module.xmip`, from the
     unit's own declaration (`ModuleEntry`), by a program in the package's
     `tools/`.
   - **`Xmip.Templates`**, beside `Xmip.Module` in `xmip-core-abi`
     (`dotnet/Xmip.Templates`), so the two packages a developer installs have
     one repository, one license and one version: `dotnet new xmip-module
     --name <Name>` gives `<Name>`, the Promote unit `OrderNumber` reading a
     JSON order's member, and `<Name>.Test`, its module naming `Xmip.Module`
     at the version both packages take from `XmipPackageVersion`, written in
     as the template is packed. The estate's walk for projects does not enter
     a template's content (`Find-XmipFile`). `xmip-template-dotnet` keeps its
     one role, the GitHub repository template for Xmip's own .NET
     repositories, AGPL-3.0-or-later like what it generates.
   - Packed locally, `.local-work/package/nuget`; published nowhere.
6. **Licenses.** Asked whether `Xmip.Module` should be permissive, so that a
   developer may keep a module closed, the owner, 2026-11-24: *Do as you
   think*. Everything a developer's code links or compiles into itself is
   Apache-2.0: all of xmip-core-abi — the C headers, the specification, the
   Rust `ffi` shapes, the bindings, `Xmip.Abi`, `Xmip.Module`,
   `Xmip.Module.Entry`, `Xmip.Templates` and the content `dotnet new` writes
   into a developer's project, and their tests. `Xmip.Testing`,
   `Xmip.Client` and crates.io's `xmip-module` will be Apache-2.0 too.
   Apache-2.0 for its patent grant, and because the AGPL-3.0 estate may keep
   using Apache-2.0 code.
   Everything else — the runtime, the node, the capabilities, the
   transports, the tools — stays AGPL-3.0-or-later (ADR-0023, amendment
   2026-11-24), and the boundary links none of it (`test/License.Test.ps1`).
   ADR-0061 decision 6 and ADR-0012 clause 9 are amended the same day. The
   PowerShell Gallery's `Xmip` module and the VS Code extension are Xmip's
   own surfaces and stay AGPL-3.0-or-later.

## Consequences

- A .NET developer writes a unit in C#, and the node cannot tell it from a
  Rust one: the same header, the same loader, the same descriptor rule.
- Each further unit capability is a table in the header first, then its
  class in `Xmip.Module`: prepare, demote, transform, validate as a unit,
  debatch, and the Work Process unit in .NET, which needs
  `xmip-core-process`'s turn form across. None is built.
- The proof that a published .NET library opens in a node runs on purpose
  (`a_dotnet_module_from_the_template_promotes_through_the_c_abi`, run with
  `XMIP_PROMOTE_LIBRARY` and `--ignored`), since a landing builds no .NET
  module.
- A module compiled with `Xmip.Module` carries Apache-2.0 code inside its
  library and stays its author's to license (clause 6). A Rust provider's
  contract still compiles `contract::export_contract!`, AGPL-3.0-or-later,
  until the `xmip-module` crate is built.

## Provenance

The question, the decision and the two rules of clause 3 are the owner's,
2026-11-24, quoted above. The recommendation he accepted, the table's shape,
the settings' transfer form, where `Xmip.Module` lives and how a unit
exports itself are the assistant's, the same day, for the owner to strike;
so is clause 6's line between Apache-2.0 and AGPL-3.0-or-later, drawn under
his *Do as you think*. `Xmip.Templates` was first built in
`xmip-template-dotnet`; asked *Should we have another repository template
after this decision?*, and shown the move beside `Xmip.Module` — one
repository, one license, one version — the owner, 2026-11-24: *Ok*.
