#requires -PSEdition Core
#requires -Version 7.7.0
# What hyperv.resource.ps1 runs for DSC, and the parts it is made of: the
# answers every template shares, the network, the machine, its hardware and
# its installation. Dot-sourcing this file brings them all, for the
# resources' entry and for test/MsdscHyperV.Test.ps1 alike.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath '../answer/MachineAnswer.ps1')
foreach ($part in 'HyperVNetwork.ps1', 'HyperVMachine.ps1', 'HyperVHardware.ps1',
    'HyperVInstallation.ps1') {
    . (Join-Path -Path $PSScriptRoot -ChildPath $part)
}

function Invoke-HyperVResource {
    <#
    .SYNOPSIS
    One operation DSC asks of a kind, and the state it answers: the instance
    as asked, with what was found (_exist, findings, and a machine's
    installation and running). set moves the instance on first; test and
    set say whether it is in its desired state, no findings. What is not
    there yet is answered absent, _exist false, never refused.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Network', 'Machine')]
        [string] $Kind,

        [Parameter(Mandatory = $true)]
        [ValidateSet('get', 'set', 'test')]
        [string] $Operation,

        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if ($Operation -eq 'set' -and $Kind -eq 'Network') {
        Set-HyperVNetwork -Instance $Instance -Confirm:$false
    }
    elseif ($Operation -eq 'set') {
        Set-HyperVMachine -Instance $Instance -Confirm:$false
    }
    [hashtable] $found = @{}
    if ($Kind -eq 'Network') {
        $found = Get-HyperVNetworkState -Instance $Instance
    }
    else {
        $found = Get-HyperVMachineState -Instance $Instance
    }
    # DSC holds the answer to the schema, whose required properties are the
    # instance's own.
    [hashtable] $state = $Instance.Clone()
    foreach ($key in $found.Keys) {
        $state[$key] = $found[$key]
    }
    if ($Operation -ne 'get') {
        $state['_inDesiredState'] = @($found['findings']).Count -eq 0
    }
    return $state
}
