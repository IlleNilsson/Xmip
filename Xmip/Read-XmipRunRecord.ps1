#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The records a run, a roll or a build leaves in its area, read in one
    place: `<kind>-<name>.toml`, each as a file and what it says.

    Style: doc/governance/powershell-style.md
#>


function Read-XmipRunRecord {
    <#
        .SYNOPSIS
            Each `<Kind>-*.toml` record in -Path: Name, what follows the
            kind in its file name; File; and Record, as Read-XmipToml read
            it. With -Name, that record alone, and nothing when it is not
            there.

        .PARAMETER Path
            The area.

        .PARAMETER Kind
            The record's kind, the start of its file name: roll, estate or
            build.

        .PARAMETER Name
            One record's name, such as a roll's pid.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidateSet('roll', 'estate', 'build')]
        [string] $Kind,

        [string] $Name = '*'
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Filter "$Kind-$Name.toml" -File)) {
        [pscustomobject] @{
            Name   = $file.BaseName.Substring($Kind.Length + 1)
            File   = $file.FullName
            Record = Read-XmipToml -Path $file.FullName
        }
    }
}
