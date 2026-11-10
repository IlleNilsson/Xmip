#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    An Essentials roll's run record: where it is and what it says.

.DESCRIPTION
    Start-XmipEssentialsRoll writes one record per roll, roll-<pid>.toml, in
    the roll area; Get-XmipTestStatus reads it, Start-XmipEssentialsRoll asks
    which rolls a cluster already has and clears the stale ones, and
    Stop-XmipTest deletes it. The name is decided here and nowhere else.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipRollRecordPath {
    <#
        .SYNOPSIS
            Where the run record of the roll with this pid is, whether or
            not it exists.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [int] $Id
    )

    return (Join-Path -Path $Path -ChildPath "roll-$Id.toml")
}


function Get-XmipRollRecord {
    <#
        .SYNOPSIS
            The run records in a roll area, each with the pid it is named for
            and what it says.

        .DESCRIPTION
            One object per record: Id, the roll's pid; File, the record's
            path; Record, the document as Read-XmipToml read it. With -Id,
            that roll's alone, and nothing when it has no record.

        .PARAMETER Path
            The roll area.

        .PARAMETER Id
            One roll's pid.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $false)]
        [int] $Id = 0
    )

    [string] $one = if ($Id -gt 0) { "$Id" } else { '*' }

    foreach ($read in @(Read-XmipRunRecord -Path $Path -Kind roll -Name $one)) {
        if ($read.Name -notmatch '^\d+$') {
            continue
        }

        [pscustomobject] @{
            Id     = [int] $read.Name
            File   = $read.File
            Record = $read.Record
        }
    }
}
