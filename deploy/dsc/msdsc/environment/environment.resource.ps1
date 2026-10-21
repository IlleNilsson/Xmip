#requires -Version 7.6

<#
    The Xmip resources an environment runs beyond one node (README.md):

    - Machine, on the machine DSC is run on: a document of this folder
      applied on another machine, which DSC itself cannot reach. The
      folder and the files the document is given are copied there over
      PowerShell Remoting — WinRM to a Windows machine as its
      Administrator, SSH to an AlmaLinux one with its key — and dsc runs
      there, elevated, with the instance's parameters.
    - Name, on the environment's DNS server: an A record for the cluster
      and for each node, in the environment's zone, holding exactly the
      addresses given.

    A resource manifest beside this file names each kind, and DSC runs this
    script with the kind and the operation, the instance's properties as
    JSON on standard input; it answers the instance's state as JSON.

    Style: doc/governance/powershell-style.md
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Machine', 'Name')]
    [string] $Kind,

    [Parameter(Mandatory = $true)]
    [ValidateSet('get', 'set', 'test')]
    [string] $Operation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($part in 'EnvironmentMachine.ps1', 'EnvironmentName.ps1') {
    . (Join-Path -Path $PSScriptRoot -ChildPath $part)
}

[hashtable] $instance = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
[hashtable] $state = if ($Kind -eq 'Machine') {
    switch ($Operation) {
        'set' {
            Set-EnvironmentMachine -Instance $instance
        }
        default {
            Get-EnvironmentMachine -Instance $instance
        }
    }
}
else {
    if ($Operation -eq 'set') {
        Set-EnvironmentName -Instance $instance
    }
    Get-EnvironmentName -Instance $instance
}

if ($Operation -eq 'test') {
    $state['_inDesiredState'] = [bool] $state._exist
}

$state | ConvertTo-Json -Compress -Depth 10
