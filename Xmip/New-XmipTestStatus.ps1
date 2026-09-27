#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The one constructor of Xmip.TestStatus, the row Get-XmipTestStatus lists.

.DESCRIPTION
    A roll and an estate run are listed side by side, so they are one shape:
    every row has every property, and what a kind of run cannot say is null.
    Get-XmipTestStatus builds a roll's row here and Get-XmipEstateRun an
    estate run's, and Xmip.Format.ps1xml shows them.

    Style: doc/governance/powershell-style.md
#>


function New-XmipTestStatus {
    <#
        .SYNOPSIS
            One Xmip.TestStatus row.

        .PARAMETER Suite
            The suite the run was started with.

        .PARAMETER Kind
            roll or pester.

        .PARAMETER State
            running, OK or FAILED, in words.

        .PARAMETER Id
            The run's process id.

        .PARAMETER Property
            The rest, by name: Cluster, StartTime, Stress, Tests, Rounds,
            Nodes, OnlineNodes, Worst, Tally, Passed, Failed, Skipped, Fault,
            Snapshot, Path, Record, Log. A name not given is null.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Suite,

        [Parameter(Mandatory = $true)]
        [ValidateSet('roll', 'pester')]
        [string] $Kind,

        [Parameter(Mandatory = $true)]
        [string] $State,

        [Parameter(Mandatory = $true)]
        [int] $Id,

        [Parameter(Mandatory = $false)]
        [hashtable] $Property = @{}
    )

    [string[]] $rest = @(
        'Cluster', 'StartTime', 'Stress', 'Tests', 'Rounds', 'Nodes', 'OnlineNodes',
        'Worst', 'Tally', 'Passed', 'Failed', 'Skipped', 'Fault', 'Snapshot', 'Path',
        'Record', 'Log'
    )

    foreach ($name in $Property.Keys) {
        if ($name -notin $rest) {
            throw "Xmip.TestStatus has no property '$name'."
        }
    }

    $row = [ordered] @{
        PSTypeName = 'Xmip.TestStatus'
        Suite      = $Suite
        Kind       = $Kind
        State      = $State
        Cluster    = $Property['Cluster']
        Id         = $Id
    }

    foreach ($name in $rest) {
        $row[$name] = $Property[$name]
    }

    return [pscustomobject] $row
}
