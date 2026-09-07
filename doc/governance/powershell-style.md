# Xmip PowerShell style

PowerShell has community conventions. These are those, plus this project's
opinions where they differ. The opinions exist because the code has to be read
and debugged by a person, not admired for being terse.

## 1. Layout

**Opening brace on the statement line.** Closing brace on its own line, aligned
with the statement that opened it.

```powershell
if ($null -eq $manifest) {
    throw 'The manifest is missing.'
}
```

**One statement per line.** No collapsed blocks, even for a single `return`.

```powershell
# No.
if (-not $Text) { return $null }

# Yes.
if ([string]::IsNullOrWhiteSpace($Text)) {
    return $null
}
```

The collapsed form cannot hold a breakpoint, and a debugger stepping through it
tells you nothing about which branch was taken.

**Four spaces, never tabs. Lines no longer than 100 characters.**

100 is a **strict recommendation**, not a law, and it was 120 until 2026-08-30
— a longer leash than the owner wanted, corrected by the owner: code shall be
readable. It is gated because gating it has paid — over one long session it
caught twenty-five real violations, including one with trailing whitespace a
grep had reported as clean. A line that genuinely needs the width, such as a URL
or a fixture string that cannot be broken without changing what it tests, is
allowed to exceed it and says why in a comment beside it.

The 89 lines that sat between 101 and 120 when the limit moved are recorded in
a per-file ratchet in the test — counted debt, not permission. Each file's
number may only shrink, and rustfmt already holds the Rust side to the same
width by default.

**Ask before breaking it.** The exception is agreed first and the reason written
into the code afterwards, never the other way round — `rust-style.md` makes the
argument in full, and it applies to an assistant more strictly than to anyone
else.

`rust-style.md` makes the same argument about file length: neither is a rule
good code never breaks, both are rules good code breaks knowingly.

**Blank line between logical steps.** A wall of twenty consecutive statements is
one step to the parser and twenty to the reader.

## 2. Functions

**A function fits on half a page — about 30 lines of body.** Longer means it is
doing more than one thing, and the fix is naming the parts rather than
scrolling.

**Of body.** The `param()` block below costs four lines per parameter, so a
three-parameter function spends fourteen lines before it does anything. Counting
that against the limit set this rule fighting the next one, and the next one
always won. `Xmip.Style.Tests.ps1` subtracts the parameter block, and a doc
comment above a nested function counts against whichever function encloses it —
which is why the pure helpers in `Sync-XmipEstate.ps1` sit at file scope.

**Full `param()` block, always.** Never the inline `function Foo($a, $b)` form,
which cannot carry attributes and hides what is mandatory.

```powershell
function Test-XmipFloor {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Minimum
    )
```

**One parameter per line, blank line between them, type on every one.**
`[AllowNull()]` and `[AllowEmptyString()]` where empty is genuinely legal — they
document what the caller may pass, which a bare `[string]` does not.

**Declare `[OutputType()]`.** PowerShell does not enforce it. It drives
completion and states intent, and a wrong one is a bug worth fixing.

**Comment-based help on anything non-obvious**, stating what it returns and
when — particularly what `$null` means.

## 3. Calls

**Name every argument.** Positional calls are a puzzle at the call site and a
silent failure when a parameter is inserted.

```powershell
# No.
Test-XmipFloor $name $found $minimum

# Yes.
Test-XmipFloor -Name $name -Found $found -Minimum $minimum
```

**Splat when a call would exceed 100 characters**, or when it takes more than
about four arguments.

```powershell
[hashtable] $install = @{
    Name                = $id
    Scope               = 'CurrentUser'
    Force               = $true
    AcceptLicense       = $true
    SkipPublisherCheck  = $true
}

Install-Module @install
```

A splat is also a value: it can be built conditionally, logged, and inspected in
the debugger, which a 200-character invocation cannot.

**Never use backtick line continuation.** Reach for a splat.

The backtick exists to make a multi-line call *pretend* to be one line, and
that is the whole problem: it treats a call that has outgrown a line as a
formatting inconvenience rather than as a call with too many arguments. The
formatting is a symptom.

A splat fixes the actual thing. The arguments become a value with a name — you
can build it conditionally, log it, assert on it, and stop on it in a debugger.
None of that is true of a 200-character invocation, and none of it is true of
the same invocation wearing backticks.

And the mechanical hazard is real on top of the design one: the character is
invisible, and **one trailing space after it silently breaks the statement** —
PowerShell stops treating it as a continuation and you get two statements that
each parse. A `grep` for a backtick at end of line reported zero in a file that
had one, because of exactly that trailing space.

Use a splat, a pipeline, or parentheses.

## 4. Values

**Single quotes unless the string expands something.** `'literal'` cannot
surprise you with a `$` and needs no escaping. Reserve `"..."` for interpolation
and subexpressions.

**Type local variables where the type matters.**

```powershell
[version] $actual = Get-XmipReportedVersion -Text $Found
[string[]] $names = @($manifest.repositories.name)
```

**`$null` on the left of a comparison.**

```powershell
if ($null -eq $actual) {
```

Not style — correctness. `$array -eq $null` *filters* the array and returns its
null elements rather than a boolean. Null on the left is always a comparison.

**Test emptiness explicitly.** `[string]::IsNullOrWhiteSpace($x)` rather than
`-not $x`, which is true for `0`, `''`, `$false` and an empty array alike.

**A loop variable is never a parameter.** Also correctness rather than taste,
and gated.

```powershell
param([string[]] $Module)

foreach ($module in $Module) { ... }    # one variable, two meanings
foreach ($name in $Module)   { ... }    # two variables
```

Variable names are case-insensitive, so `$module` and `$Module` are the same
storage. The loop still runs — the enumerator was taken before the first
assignment — but every read inside the body is ambiguous, and the array the
caller passed is gone after the first iteration.

Both `Test-XmipModule` and `Submit-XmipModule` were written this way and neither
misbehaved visibly, because `Join-Path`, `Write-Host` and `ShouldProcess` all
accept an array and do something plausible with one. It surfaced on 2026-08-29
only when the variable reached a `[string]` parameter, which refused it. The
second instance was in the function that commits and pushes the estate.

**Explicit `return`.** PowerShell's implicit output is real and useful; it is
also how a stray expression ends up in a function's return value. Say what comes
back.

**Declare, then branch. Never assign a default you would immediately
overwrite.** This is the one rule here that was learned rather than imported.

```powershell
# No. $Path[-2] is evaluated for every caller, including the ones where
# $Path has a single segment, and those throw IndexOutOfRange.
[string[]] $topics = @('technology', $Path[-2], $Path[-1])

if (-not $isImplementation) {
    $topics = @($domain.ToLowerInvariant())
}

# Yes. Each expression is evaluated only where it is valid.
[string[]] $topics = @()

if ($isImplementation) {
    $topics = @('technology', $Path[-2], $Path[-1])
}
else {
    $topics = @($domain.ToLowerInvariant())
}
```

Default-then-override *reads* as though the default is provisional. It is not:
it is an unconditional statement, and it runs before the condition that would
have excused it. `Resolve-XmipNodeFacts` acquired this defect during a restyle,
threw on `xmip.core`, and took four failing tests to find.

The declarative form is the second one, even though it is longer — the
condition governs the expression rather than following it. Where the value is a
simple constant and the expression cannot fail, a default is fine. The rule
bites when the default *computes* something.

## 5. Behaviour

**`Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`** at the
top of every entry point.

**An operation switch means do it. `-WhatIf` means do not.** There is no
`-Apply`. Reporting is the default and needs no ceremony to reach.

**`SupportsShouldProcess` on anything that changes the world**, and call
`$PSCmdlet.ShouldProcess()` before it changes.

**A failed precondition is an error, not a warning.** `Write-Error
-ErrorAction Stop` or `throw`, so `$?` is false and CI notices. A rule that
reports and returns success is not a rule.

**A script writes to the streams. Capturing them is the caller's business,
with `*>`.** No `Start-Transcript`, no `-LogPath` parameter, no logging
framework. PowerShell already has redirection and it works on any command.

```powershell
& { ... } 6>&1 5>&1 4>&1 3>&1 2>&1 | Tee-Object -FilePath D:\Repos\land.log
```

There are six redirectable streams, and a seventh that cannot be redirected:

| # | Stream | Written by |
| --- | --- | --- |
| 1 | Success | `Write-Output` |
| 2 | Error | `Write-Error`, and a native command's stderr |
| 3 | Warning | `Write-Warning` |
| 4 | Verbose | `Write-Verbose` |
| 5 | Debug | `Write-Debug` |
| 6 | Information | `Write-Information`, **`Write-Host`** |
| — | Progress | `Write-Progress` — no redirection exists |

**Only Success can be redirected *into*.** `n>&1` is the only merge direction
PowerShell has, so anything `Tee-Object` is expected to see must be merged into
Success first — one operator per stream, and each one is easy to forget.

`Write-Host` writing to Information rather than Success is the trap: a script
that reports its progress with `Write-Host` produces a log that looks complete
and contains none of it, unless `6>&1` is there.

`*>` is not this. It sends every stream to a *file* and nothing to the console,
which leaves the operator watching an empty terminal while the log fills up.
Useful for an unattended run and wrong for a run somebody is watching.

See [about_Redirection](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_redirection).

**A script that builds its own log file is a script that decided for its
caller.** It writes where it wants, it names the file what it wants, and it
still cannot be redirected somewhere else without a parameter nobody asked for.

**A native command's output goes through the streams too**, so it lands in the
same redirect:

```powershell
& git -C $Directory @Arguments 2>&1 | ForEach-Object { Write-Host "     git| $_" }
```

## 6. What this is enforced by

`tests/Xmip.Style.Tests.ps1`, over `Xmip/` and `tests/`. It fails on:

| Rule | Section | Enforced |
| --- | --- | --- |
| Line over 100 characters | 1 | yes, with a per-file ratchet |
| Backtick line continuation | 3 | yes |
| A loop variable that is a parameter | 4 | yes |
| A file that does not parse | — | yes |
| Function over 35 lines | 2 | **reported, not gated** |

**This table is checked.** Every gating test in `Xmip.Style.Tests.ps1` must have
a row here, and the count is asserted. The loop-variable rule was gated on
2026-08-29 and went undocumented, because the only checks on this document were
that it names the test file and states the line length — neither of which any
new rule would touch. A document that describes what is enforced has to fail
when it stops doing so.

Findings are returned as objects, not printed as text, so a failure can be
grouped and sorted rather than read:

```powershell
Get-XmipStyleFinding | Group-Object Rule
Get-XmipStyleFinding | Where-Object Rule -eq 'LineLength' | Format-Table
```

Function length is measured with the PowerShell AST, and a function is charged
only for its own lines — a cmdlet that contains eight nested helpers is not
blamed for their length, because that number would hide which helper is
actually too long.

**Function length was a gate and is now a report, and the reason is worth
keeping.** It ran with a waiver list that reached sixteen entries. Over one long
session the line-length rule caught twenty-five real violations and the backtick
rule caught five — including one with trailing whitespace that a `grep` had
reported as zero. The length gate caught **nothing**. Every failure it produced
was a waiver number needing adjustment, four times consecutively, while the work
it interrupted waited.

A rule whose only output is maintenance of its own exception list is not
enforcing anything.

Length was also the wrong measure. `New-TransactionReport` is thirty-eight lines
of which twenty are a single hashtable literal — that is a shape, not
complexity — while a short function with deeply nested branches sails through.
So the report prints **branches** beside length: `if` and `elseif` clauses,
loops, `switch` clauses, `catch` blocks, ternaries, and `-and` / `-or`, which
are branches wearing an operator. That number is the one to read.

Gate it again only with evidence: a real defect it would have caught, and a
threshold taken from measured data rather than guessed.

The rules this file does **not** yet enforce are the ones needing judgement:
one statement per line, named arguments, single quotes where nothing expands.
They are stated above and reviewed by people. Listing them here as enforced
when they are not is the failure mode this section already had once —
`Xmip.Style.Tests.ps1` was named here for some time before it existed.

Style that is only written down decays. ADR-0021 made that argument about
version floors, and it applies equally here.
