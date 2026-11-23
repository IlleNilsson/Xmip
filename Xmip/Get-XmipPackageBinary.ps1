#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Where cargo puts a build its arguments ask for: the target directory,
    the triple's folder and the profile's, `measured` among them.

.DESCRIPTION
    Apart from New-XmipPackage.ps1 since 2026-11-20: the service's build,
    the package's and the System Tests' service read it.

    Style: doc/governance/powershell-style.md
#>

function Get-XmipPackageBinary {
    <#
        .SYNOPSIS
            Where cargo puts the build its arguments ask for — the target
            directory, and under it the triple's folder with --target and the
            profile's — and the architecture it is for.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $CargoArgument
    )

    [string] $triple = ''
    [int] $at = [Array]::IndexOf($CargoArgument, '--target')

    if ($at -ge 0 -and $at + 1 -lt $CargoArgument.Count) {
        $triple = $CargoArgument[$at + 1]
    }

    [string] $architecture = if ($triple) {
        if ($triple -like 'aarch64-*') { 'arm64' } else { 'x64' }
    }
    else {
        [string] $os = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        if ($os -eq 'Arm64') { 'arm64' } else { 'x64' }
    }

    # cargo's folder for the profile: `--profile <name>` builds in <name>
    # (`measured` among them), `dev` and no profile in debug.
    [int] $named = [Array]::IndexOf($CargoArgument, '--profile')
    [string] $profileName = if ($named -ge 0 -and $named + 1 -lt $CargoArgument.Count -and
        $CargoArgument[$named + 1] -ne 'dev') {
        $CargoArgument[$named + 1]
    }
    elseif ($CargoArgument -contains '--release') { 'release' }
    else { 'debug' }
    [string] $target = (Get-XmipEstateLayout -Root $Root).Build

    [string] $folder = if ($triple) { "$triple/$profileName" } else { $profileName }

    [pscustomobject] @{
        Target       = $target
        Folder       = $folder
        Architecture = $architecture
    }
}
