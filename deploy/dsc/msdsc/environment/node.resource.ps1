#requires -Version 7.6

<#
    The Xmip resources a node machine runs (README.md): what Microsoft DSC
    v3 has no built-in resource for, on Windows and on AlmaLinux alike. A
    resource manifest beside this file names each kind, and DSC runs this
    script with the kind and the operation, the instance's properties as
    JSON on standard input; it answers the instance's state as JSON.

    - Account: the node's service account, made where it is not there. On
      Windows a virtual account, NT SERVICE\xmip-<node>, exists with its
      service and is never made.
    - File: a file in place, the same bytes as its source; private where
      asked, readable by its owner alone.
    - Package: the estate's package installed, which runs xmip-service
      --install with the node, the cluster and the account.
    - Slice: the node's configuration, xmip-node.toml, as xmip-service
      --slice prints it from the cluster's xmip.toml; the service is
      restarted when it changed.
    - Opening: a firewall opening for each port xmip-service --listening
      says the node's configuration listens on, and no other.
    - Service: the node's service running and started with the machine.

    Every rule about the node is xmip-service's; this only asks it and puts
    files where it reads them.

    Style: doc/governance/powershell-style.md
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Account', 'File', 'Package', 'Slice', 'Opening', 'Service')]
    [string] $Kind,

    [Parameter(Mandatory = $true)]
    [ValidateSet('get', 'set', 'test')]
    [string] $Operation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($part in 'NodeMachine.ps1', 'NodeFile.ps1', 'NodeOpening.ps1') {
    . (Join-Path -Path $PSScriptRoot -ChildPath $part)
}

[hashtable] $instance = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
[hashtable] $state = switch ($Operation) {
    'get' {
        Get-NodeMachineState -Kind $Kind -Instance $instance
    }
    'test' {
        [hashtable] $found = Get-NodeMachineState -Kind $Kind -Instance $instance
        $found['_inDesiredState'] = Test-NodeMachineState -State $found
        $found
    }
    'set' {
        Set-NodeMachineState -Kind $Kind -Instance $instance
        Get-NodeMachineState -Kind $Kind -Instance $instance
    }
}

$state | ConvertTo-Json -Compress -Depth 10
