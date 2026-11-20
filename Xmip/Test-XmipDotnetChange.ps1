#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The landing's .NET part: every .NET project a landing changed or
    consumes, and a changed crate's other languages.

.DESCRIPTION
    Run beside the Rust part (Invoke-XmipLandingPart), against the copy of
    the runtime's library the landing built first.

    Style: doc/governance/powershell-style.md
#>


function Test-XmipDotnetChange {
    <#
        .SYNOPSIS
            Builds and tests each module's .NET projects and Pester tests, a
            Rust module's TypeScript shell and its Event bindings; the module
            that failed, or nothing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Module
    )

    foreach ($name in $Module) {
        [string] $path = Join-Path -Path $RepositoryRoot -ChildPath $name
        [string] $shell = Join-Path -Path $path -ChildPath 'extension'
        Write-Host "== $name (.NET and other languages)" -ForegroundColor Cyan

        # The one Rust repository that also ships a TypeScript shell
        # (ADR-0014, amendment 2026-09-10).
        if ((Test-Path -LiteralPath (Join-Path $shell 'package.json')) -and
            -not (Test-XmipExtensionShell -Path $shell -Name $name)) {
            return $name
        }

        # Until 2026-11-16 only cargo ran for a Rust repository that also
        # carries .NET, so Xmip.Surface, Xmip.Operate and Xmip.Abi landed with
        # their tests never run.
        if (@(Find-XmipFile -Path $path -Filter '*.csproj').Count -gt 0 -and
            -not (Test-XmipDotnetModule -Path $path -Name $name)) {
            return $name
        }

        # The Event bindings in the languages besides Rust (ADR-0065).
        if ((Test-Path -LiteralPath (Join-Path $path $script:XmipEventBinding)) -and
            -not (Test-XmipEventBinding -Path $path -Name $name)) {
            return $name
        }
    }
}
