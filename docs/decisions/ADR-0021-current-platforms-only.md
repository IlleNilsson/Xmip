# ADR-0021: Current platforms only

- Status: Accepted
- Date: 2026-08-25
- Related: ADR-0012 (module boundary), ADR-0015 (packaging), ADR-0020 (documentation structure)

## In brief

- Theme: Operating Xmip
- Subject: Current platforms only
- Name: Current platforms only
- Order: 3
- Concepts: Pester, PowerShell, .NET, Rust versions; Version floors, channels

Xmip tracks the current stable release of every platform it depends on and
carries no compatibility with superseded ones. PowerShell 7.6.5 Core, .NET 11,
latest stable Rust, Pester 6.

**The version numbers are not the decision** — they will be history soon enough.
The decision is the rule that produced them, which is why `prerequisite.toml`
and `rust-toolchain.toml` express channels rather than pins. A floor states what
would break; it does not freeze anything.

## Context

Xmip is new. Nothing depends on it, no customer is mid-migration, and there is
no installed base to protect. That is a position every platform occupies exactly
once, and it is worth spending deliberately rather than losing by default.

BizTalk is the cautionary case and the one Xmip is measured against. Its
compatibility burden is a large part of why it ossified: each release had to
carry the previous one, the .NET Framework it was built on could not move, and
by the end the effort of *not breaking* consumed the effort available for
*improving*. The technology was not the problem. The accumulated promise was.

The specific question that prompted this: whether PowerShell 5.1 or 6 should be
supported by the tooling, and whether `#requires -Version 7.0` or `7.6` is
right.

## Why this is realistic rather than hostile

The usual objection to a current-only policy is that it strands users. For the
platforms Xmip depends on, it does not, and that is what makes the policy
affordable:

- **.NET consumers move quickly.** The release cadence is annual, support
  windows are short and well published, and the ecosystem has been trained by a
  decade of it. An organisation running .NET is already on a rapid path.
- **PowerShell users on Windows move quickly too.** Note the distinction:
  *PowerShell on Windows* is PowerShell 7 running on a Windows machine, and
  those installations update through winget, the Store or the MSI on a fast
  cycle. **Windows PowerShell** — the proper noun, 5.1, on .NET Framework — is a
  different product that ships with the operating system and does not move at
  all. Xmip requires the first and cannot use the second. `#requires -PSEdition
  Core` is what draws that line.
- **Rust has no long-term-support branch to speak of.** Stable ships every six
  weeks and the ecosystem follows; pinning is the unusual choice, not tracking.

So the burden a current-only policy places on an adopter is one they are
already carrying for other reasons. That is the difference between this and
demanding an upgrade nobody else is asking for.

## Decision

**Xmip targets current platforms. It does not carry compatibility with
superseded ones.**

Concretely, at the time of writing:

| | Xmip requires | Explicitly not supported |
| --- | --- | --- |
| PowerShell | 7.6.5 or later, Core edition | Windows PowerShell (5.1, .NET Framework) |
| .NET | 11 | 8, 9, 10 |
| Rust | latest stable, via `rust-toolchain.toml` | any pinned older toolchain |
| Pester | 6 or later | 3, 5 |

**These numbers are not the decision.** They will be old by the time Xmip is in
wide use anywhere, and quoting them in five years will be quoting history. The
decision is the rule that produced them:

> Track the current stable release of every platform Xmip depends on. Where a
> preview is the only way to reach a needed capability, track the preview and
> record the date it becomes stable. Do not accumulate support for what a
> platform has already superseded.

This is why `prerequisite.toml` and `rust-toolchain.toml` express **channels**
rather than pins — `channel = "stable"`, `channel = "preview"` — and why a
`minimum` is a floor rather than a target. A floor states what would break; it
does not freeze anything.

### Corollaries

**A version floor is a real refusal.** `#requires -PSEdition Core` and
`#requires -Version 7.6.5` are not advisory. A machine below the floor is told so
by PowerShell, by name and version, and nothing runs. That error message *is*
the compatibility documentation.

**PowerShell is the one prerequisite Xmip cannot install for you**, because the
tooling is written in it. Everything else — git, Rust, the linker, PSToml,
Pester, .NET — `Install-XmipPrerequisite` reports and can install.

**A newer major version is refused, not guessed at.** `Get-XmipManifest` accepts
schema 2.x and refuses 3.0, because a major bump may have moved something the
reader would then silently misread. Tracking current is not the same as
accepting anything.

**The estate is a customer of this rule too.** `xmip-core-transport-modbus`
speaks to hardware that predates all of the above by decades, and that is
correct: **Xmip integrates with ancient systems, it does not run on them.** The
protocols in `identity-by-technology.md` go back to the 1970s. The runtime does
not.

## Consequences

- Windows PowerShell 5.1 users cannot run Xmip tooling. That is intended, and
  it removes an entire class of "works differently on Desktop edition" defect.
- CI tracks stable rather than a pinned toolchain, so a Rust release can break
  the build. That is the cost, and it is paid in small, immediate increments
  rather than in one large migration later.
- A .NET preview dependency means a dated obligation: `prerequisite.toml`
  records that .NET 11 is preview until 10 November 2026 and what to change on
  that date.
- Where a deployment genuinely cannot move — an air-gapped site, a regulated
  estate on a frozen image — the answer is a purpose-compiled runtime pinned at
  build time per `deployment-model.md`, not a compatibility branch in the
  mainline.

## Alternatives considered

**Support the previous major of each platform.** The conventional choice, and
the one that produced BizTalk's position. Rejected: it doubles the test matrix
for a user base that does not exist yet, and the second version is always the
one nobody actually runs but everything must accommodate.

**Pin exact versions rather than channels.** Reproducible, and wrong for a
project at this stage. A pin ages silently — nothing fails, the numbers simply
become false — whereas a channel that breaks tells you immediately, while the
change is small.

**Decide per platform rather than as a rule.** Rejected: that is how a policy
becomes a set of unrelated version numbers nobody can defend, which is the
state this ADR was written to leave.
