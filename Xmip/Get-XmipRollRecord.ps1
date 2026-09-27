#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    A Playground roll's run record: where it is and what it says.

.DESCRIPTION
    Start-XmipPlaygroundRoll writes one record per roll, roll-<pid>.toml, in
    the roll area; Get-XmipTestStatus reads it, Start-XmipPlaygroundRoll asks
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

    [System.IO.FileInfo[]] $files = @()

    if ($Id -gt 0) {
        [string] $one = Get-XmipRollRecordPath -Path $Path -Id $Id
        $files = @(Get-Item -LiteralPath $one -ErrorAction SilentlyContinue)
    }
    elseif (Test-Path -LiteralPath $Path -PathType Container) {
        $files = @(Get-ChildItem -LiteralPath $Path -Filter 'roll-*.toml' -File)
    }

    foreach ($file in $files) {
        [string] $number = $file.BaseName -replace '^roll-', ''

        if ($number -notmatch '^\d+$') {
            continue
        }

        [pscustomobject] @{
            Id     = [int] $number
            File   = $file.FullName
            Record = Read-XmipToml -Path $file.FullName
        }
    }
}
