#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Running the platform repository's own tests during a landing.

.DESCRIPTION
    Apart from Test-XmipChangeTree.ps1 since 2026-10-13, when the landing's
    progress line would have taken that file past the 400 lines the estate
    allows a file.

    Style: doc/governance/powershell-style.md
#>


function Test-XmipPlatform {
    <#
        .SYNOPSIS
            Runs the platform repository's own tests, every file of test/, in a
            fresh pwsh, and says whether they passed.

        .DESCRIPTION
            A change to the root — the landing scripts and their tests among it —
            went straight to the pin step unverified (an external review,
            2026-10-05).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    Write-Host '== the platform repository (test/)' -ForegroundColor Cyan

    [string] $tests = Join-Path -Path $RepositoryRoot -ChildPath 'test'
    [string] $manifest = Join-Path -Path $PSScriptRoot -ChildPath 'Xmip.psd1'

    # The estate suite's own Pester configuration — its *.Test.ps1 names
    # among it — never a second one written here.
    [scriptblock] $run = {
        param([string] $Manifest, [string] $Path)

        Import-Module -Name $Manifest
        [PesterConfiguration] $configuration = & (Get-Module -Name Xmip) {
            param([string] $Path) Get-XmipPesterConfiguration -Path $Path
        } $Path
        $configuration.Run.Exit = $true
        $configuration.Output.Verbosity = 'Normal'
        Invoke-Pester -Configuration $configuration
    }

    & pwsh -NoProfile -Command $run -args $manifest, $tests 2>&1 |
        ForEach-Object { Write-Host $_ }

    $LASTEXITCODE -eq 0
}
