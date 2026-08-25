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

**Four spaces, never tabs. Lines no longer than 120 characters.**

**Blank line between logical steps.** A wall of twenty consecutive statements is
one step to the parser and twenty to the reader.

## 2. Functions

**A function fits on half a page — about 30 lines.** Longer means it is doing
more than one thing, and the fix is naming the parts rather than scrolling.

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

**Splat when a call would exceed 120 characters**, or when it takes more than
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

**Never use backtick line continuation.** It is invisible, and one trailing
space after it silently breaks the statement. Use a splat, a pipeline, or
parentheses.

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

## 6. What this is enforced by

`tests/Xmip.Style.Tests.ps1`, over `Xmip/` and `tests/`. It fails on:

| Rule | Section | Enforced |
| --- | --- | --- |
| Line over 120 characters | 1 | yes |
| Backtick line continuation | 3 | yes |
| Function over 35 lines | 2 | yes, with a waiver list |
| A file that does not parse | — | yes |

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

**The waiver list is a ratchet, not an exemption.** Four functions predate this
document: `Install-XmipPrerequisite`, `Sync-XmipEstate`, `Sync-XmipRepository`
and `Invoke-Distribute`. Each is recorded at the length it had when the rule
arrived. A recorded number may fall and an entry may leave; a function that
grows past its own waiver fails. Adding an entry is a decision, taken in the
open, which is the difference between a known debt and a broken rule.

The rules this file does **not** yet enforce are the ones needing judgement:
one statement per line, named arguments, single quotes where nothing expands.
They are stated above and reviewed by people. Listing them here as enforced
when they are not is the failure mode this section already had once —
`Xmip.Style.Tests.ps1` was named here for some time before it existed.

Style that is only written down decays. ADR-0021 made that argument about
version floors, and it applies equally here.
