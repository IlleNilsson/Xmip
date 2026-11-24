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
            Rust module's TypeScript shell and its Event bindings: what failed,
            as Xmip.PartFailure, the module and the project or the check, or
            nothing.

        .PARAMETER Alone
            Every module to its end, for Core.Internal, so every failure is
            named; a landing stops at its first.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.PartFailure')]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Module,

        [Parameter()]
        [switch] $Alone
    )

    foreach ($name in $Module) {
        [string] $path = Join-Path -Path $RepositoryRoot -ChildPath $name
        [string] $shell = Join-Path -Path $path -ChildPath 'extension'
        Write-Host "== $name (.NET and other languages)" -ForegroundColor Cyan

        # The first check that fails names the module; the next are not run.
        [object[]] $failed = @(
            # The one Rust repository that also ships a TypeScript shell
            # (ADR-0014, amendment 2026-09-10).
            if ((Test-Path -LiteralPath (Join-Path $shell 'package.json')) -and
                -not (Test-XmipExtensionShell -Path $shell -Name $name)) {
                New-XmipPartFailure -Module $name -Test 'its extension shell' -Message (
                    'did not compile')
            }
            # Until 2026-11-16 only cargo ran for a Rust repository that also
            # carries .NET, so Xmip.Surface, Xmip.Operate and Xmip.Abi landed
            # with their tests never run.
            elseif (@(Find-XmipModuleProject -Path $path).Count -gt 0) {
                Test-XmipDotnetModule -Path $path -Name $name
            }
        )

        # The Event bindings in the languages besides Rust (ADR-0065).
        if ($failed.Count -eq 0 -and
            (Test-Path -LiteralPath (Join-Path $path $script:XmipEventBinding)) -and
            -not (Test-XmipEventBinding -Path $path -Name $name)) {
            $failed = @(New-XmipPartFailure -Module $name -Test 'its Event bindings' -Message (
                    'an Event binding failed'))
        }

        $failed

        if ($failed.Count -gt 0 -and -not $Alone) {
            return
        }
    }
}
