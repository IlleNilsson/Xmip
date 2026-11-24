#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The one constructor of Xmip.TestStatus, the row Get-XmipTestStatus lists.

.DESCRIPTION
    A roll and an estate run are listed side by side, so they are one shape:
    every row has every property, and what a kind of run cannot say is null.
    Get-XmipTestStatus builds a roll's row here and Get-XmipEstateRun an
    estate run's, and Xmip.Format.ps1xml shows them. A run on a test
    computer is the row that computer's estate built, made again here with
    ComputerName saying where it runs.

    Style: doc/governance/powershell-style.md
#>


# Every property of a row beside Suite, Kind, State and Id.
[string[]] $script:XmipTestStatusProperty = @(
    'Cluster', 'StartTime', 'Stress', 'Tests', 'Rounds', 'Nodes', 'NodeCapability',
    'RealNodes', 'Worst', 'Tally', 'Passed', 'Failed', 'Skipped', 'Fault', 'Snapshot',
    'Path', 'Record', 'Log', 'Hidden', 'ComputerName'
)


function New-XmipTestStatus {
    <#
        .SYNOPSIS
            One Xmip.TestStatus row.

        .PARAMETER Suite
            The suite the run was started with.

        .PARAMETER Kind
            roll, pester, or build: a roll still building, before it rolls
            (Get-XmipSystemTestBuild); internal, a run of the internal tests
            of named modules (Start-XmipInternalSuite); or demo, a run of the
            demo readiness check (Get-XmipDemoRun).

        .PARAMETER State
            running, building, ended, OK or FAILED, in words.

        .PARAMETER Id
            The run's process id.

        .PARAMETER Property
            The rest, by name: Cluster, StartTime, Stress, Tests, Rounds,
            Nodes, NodeCapability (each node's Node capabilities,
            <node>=online+erp-direct), RealNodes, Worst, Tally, Passed, Failed,
            Skipped, Fault, Snapshot, Path, Record, Log, Hidden and
            ComputerName, the test computer it runs on, null for this one. A
            name not given is null.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Suite,

        [Parameter(Mandatory = $true)]
        [ValidateSet('roll', 'pester', 'internal', 'build', 'demo')]
        [string] $Kind,

        [Parameter(Mandatory = $true)]
        [string] $State,

        [Parameter(Mandatory = $true)]
        [int] $Id,

        [Parameter(Mandatory = $false)]
        [hashtable] $Property = @{}
    )

    [string[]] $rest = $script:XmipTestStatusProperty

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


function ConvertFrom-XmipTestComputerStatus {
    <#
        .SYNOPSIS
            A row a test computer's estate answered, as this estate's
            Xmip.TestStatus, ComputerName saying which computer; Path, Record
            and Log are that computer's.

        .PARAMETER InputObject
            A row as it crossed, deserialized.

        .PARAMETER ComputerName
            The computer it came from.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject] $InputObject,

        [Parameter(Mandatory = $true)]
        [string] $ComputerName
    )

    process {
        [hashtable] $property = @{ ComputerName = $ComputerName }

        foreach ($name in $script:XmipTestStatusProperty) {
            if ($name -ne 'ComputerName' -and $InputObject.PSObject.Properties[$name]) {
                $property[$name] = $InputObject.$name
            }
        }

        [hashtable] $row = @{
            Suite = [string] $InputObject.Suite
            Kind  = [string] $InputObject.Kind
            State = [string] $InputObject.State
            Id    = [int] $InputObject.Id
        }

        New-XmipTestStatus @row -Property $property
    }
}
