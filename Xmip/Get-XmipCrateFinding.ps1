#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Where a Cargo.toml names an estate crate other than the way the manifest says.

.DESCRIPTION
    Apart from Sync-XmipEstate.ps1 since 2026-09-22, when that file was 1,303 lines
    against the 400 the estate allows, and the owner asked for the estate to be
    consolidated. Reconciling the estate is one command made of several subjects;
    each subject is a file.

    Style: doc/governance/powershell-style.md
#>


<#
    .SYNOPSIS
    What a module's Cargo.toml should say, against what it says.

    .DESCRIPTION
    Two things are reconciled, both derived rather than maintained.

    **The Cargo package name is the repository name.** architecture.toml sets
    primaryCrateMatchesRepository. A dependency may use a shorter local key,
    such as `xmip-message`, while its package remains `xmip-core-message`.

    **A dependency rev is the commit the superproject pins.** Otherwise the
    estate is wired twice and the two wirings drift without anyone noticing.

    Returns one finding per line that needs changing. Nothing is written here.
#>
function Get-XmipCrateFinding {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [hashtable] $MountOf,

        [Parameter(Mandatory = $true)]
        [hashtable] $PinnedAt
    )

    foreach ($name in ($MountOf.Keys | Sort-Object)) {
        [string] $file = Join-Path $Root (Join-Path $MountOf[$name] 'Cargo.toml')

        if (-not (Test-Path -LiteralPath $file)) {
            continue
        }

        [string[]] $lines = @(Get-Content -LiteralPath $file)

        for ([int] $index = 0; $index -lt $lines.Count; $index++) {
            $finding = Test-XmipCrateLine -Line $lines[$index] -PinnedAt $PinnedAt

            if ($null -eq $finding) {
                continue
            }

            $finding | Add-Member -NotePropertyName File -NotePropertyValue $file
            $finding | Add-Member -NotePropertyName Line -NotePropertyValue ($index + 1)
            $finding | Add-Member -NotePropertyName Module -NotePropertyValue $name
            $finding
        }
    }
}


<#
    .SYNOPSIS
    Whether one Cargo.toml line disagrees with the estate, and what it should be.
#>
function Test-XmipCrateLine {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Line,

        [Parameter(Mandatory = $true)]
        [hashtable] $PinnedAt
    )

    # Cargo package identity is validated against the repository by the estate
    # manifest and template. A shorter dependency key is only a local alias; the
    # package remains, for example, xmip-core-message.

    # xmip-core = { git = "...", rev = "..." }
    if ($Line -notmatch '^\s*(xmip[\w-]*)\s*=\s*\{.*\brev\s*=\s*"([0-9a-f]+)"') {
        return $null
    }

    [string] $dependency = $Matches[1]
    [string] $rev = $Matches[2]
    [string] $should = [string] $PinnedAt[$dependency]

    if ([string]::IsNullOrEmpty($should) -or $rev -ceq $should) {
        return $null
    }

    return [pscustomobject]@{
        Rule = 'DependencyRev'
        Was  = "$dependency $($rev.Substring(0, 7))"
        Is   = "$dependency $($should.Substring(0, 7))"
        New  = $Line -replace '\brev\s*=\s*"[0-9a-f]+"', "rev = `"$should`""
    }
}
