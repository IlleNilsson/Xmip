#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    A System Tests roll's run record: where it is and what it says.

.DESCRIPTION
    Start-XmipSystemTestRoll writes one record per roll, roll-<pid>.toml, in
    the roll area; Get-XmipTestStatus reads it, and lists the roll from it
    after the roll ended, Start-XmipSystemTestRoll asks which rolls a cluster
    already has and clears that cluster's ended ones as it starts it again,
    and Stop-XmipTest deletes it. The name is decided here and nowhere else.
    Get-XmipTestResult reads the snapshot the latest shown one names.

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


function Get-XmipLatestRollSnapshot {
    <#
        .SYNOPSIS
            The snapshot of the roll started last in a roll area, running or
            ended. Empty where no record names one.

        .PARAMETER Path
            The roll area.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $latest = @(
        Get-XmipRollRecord -Path $Path |
            Sort-Object -Property {
                [datetimeoffset]::Parse(
                    [string](Get-TomlValue -Node $_.Record -Name 'started' -Default '0001-01-01T00:00:00Z'),
                    [cultureinfo]::InvariantCulture).UtcDateTime
            }
    ) | Select-Object -Last 1

    if ($null -eq $latest) {
        return ''
    }

    return [string](Get-TomlValue -Node $latest.Record -Name 'snapshot' -Default '')
}
