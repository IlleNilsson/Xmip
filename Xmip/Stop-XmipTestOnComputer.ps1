#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Stopping runs on a test computer, for Stop-XmipTest -ComputerName and
    for a run on the pipeline from Get-XmipTestStatus -ComputerName.

.DESCRIPTION
    That computer's own Stop-XmipTest stops them, in the copy of the estate
    Start-XmipTest -ComputerName sent there (Invoke-XmipTestComputer), once
    this one's -WhatIf and -Confirm have allowed it (the owner, 2026-11-23:
    "Do what you recommend").

    Style: doc/governance/powershell-style.md
#>


function Stop-XmipTestOnComputer {
    <#
        .SYNOPSIS
            Stops, on each computer, the runs -ComputerName and the filters
            pick, and the runs piped from there by their ids; a refusal
            there is this command's.

        .PARAMETER Caller
            Stop-XmipTest itself, for ShouldProcess.

        .PARAMETER Bound
            What Stop-XmipTest was called with.

        .PARAMETER Piped
            The ids of runs on the pipeline, by the computer each runs on.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet] $Caller,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound,

        [Parameter(Mandatory)]
        [hashtable] $Piped
    )

    [hashtable] $asked = @{}

    foreach ($there in @($Piped.Keys)) {
        $asked[$there] = @{ Id = [int[]] @($Piped[$there]) }
    }

    # The filters as Stop-XmipTest was given them, there.
    if ($Bound.ContainsKey('ComputerName')) {
        [hashtable] $given = @{}

        foreach ($name in 'Id', 'Suite', 'Test') {
            if ($Bound.ContainsKey($name)) {
                $given[$name] = $Bound[$name]
            }
        }

        $asked[[string] $Bound['ComputerName']] = $given
    }

    foreach ($there in @($asked.Keys)) {
        Stop-XmipTestThere -Caller $Caller -ComputerName $there -Parameter $asked[$there]
    }
}


function Stop-XmipTestThere {
    <#
        .SYNOPSIS
            Stops the runs -Parameter picks on one computer, through its own
            Stop-XmipTest, and audits it here.

        .PARAMETER Parameter
            What that computer's Stop-XmipTest is given: -Id, or the filters.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet] $Caller,

        [Parameter(Mandatory)]
        [string] $ComputerName,

        [Parameter(Mandatory)]
        [hashtable] $Parameter
    )

    $computer = Read-XmipTestComputer -Name $ComputerName
    [string] $picked = @(
        $Parameter.Keys | Sort-Object | ForEach-Object { "-$_ $(@($Parameter[$_]) -join ',')" }
    ) -join ' '

    if ($picked -eq '') {
        $picked = 'no filter'
    }

    if (-not $Caller.ShouldProcess("the runs on $ComputerName picked by $picked", 'Stop')) {
        return
    }

    $Parameter.Confirm = $false
    $null = Invoke-XmipTestComputer -Computer $computer -Command Stop-XmipTest -Parameter $Parameter
    Write-XmipAudit -Action 'Stop-XmipTest' -Phase Finished -Property @{
        ComputerName = $ComputerName
        Picked       = $picked
    }
}
