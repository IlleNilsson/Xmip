#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The Xmip resources an environment runs beyond one node (README.md):

    - Machine, on the machine DSC is run on: a document of this folder
      applied on another machine, which DSC itself cannot reach. The
      folder and the files the document is given are copied there —
      PowerShell Remoting over WinRM to a Windows machine as its
      Administrator, OpenSSH to an AlmaLinux one with the environment's key
      and known_hosts, DSC itself brought there first — and dsc runs there,
      elevated, with the instance's parameters.
    - Slice, on the machine DSC is run on: a node's configuration sliced from
      the cluster's cluster.xmip and signed by the environment's authority,
      with that authority's certificate, written where Machine ships them
      from: a node never slices (ADR-0031, amendment 2026-11-06).
    - Name, on the environment's DNS server: an A record for the cluster
      and for each node, in the environment's zone, holding exactly the
      addresses given.
    - Started, on the machine DSC is run on: every node of the environment
      running, started together, since none of a cluster's nodes accepts
      work until its Xmip Storage does (EnvironmentStarted.ps1).

    A resource manifest beside this file names each kind, and DSC runs this
    script with the kind and the operation, the instance's properties as
    JSON on standard input; it answers the instance's state as JSON.

    Style: doc/governance/powershell-style.md
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Machine', 'Slice', 'Name', 'Started')]
    [string] $Kind,

    [Parameter(Mandatory = $true)]
    [ValidateSet('get', 'set', 'test')]
    [string] $Operation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# The Windows machines' secret is read as every template reads it: deploy/dsc/machine.
foreach ($part in '../../machine/MachineSecret.ps1', 'Program.ps1', 'EnvironmentSsh.ps1',
    'EnvironmentMachine.ps1', 'EnvironmentSlice.ps1', 'EnvironmentName.ps1',
    'EnvironmentStarted.ps1') {
    . (Join-Path -Path $PSScriptRoot -ChildPath $part)
}

[hashtable] $instance = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
[hashtable] $state = switch ($Kind) {
    'Machine' {
        if ($Operation -eq 'set') {
            Set-EnvironmentMachine -Instance $instance
        }
        else {
            Get-EnvironmentMachine -Instance $instance
        }
    }
    'Slice' {
        if ($Operation -eq 'set') {
            Set-EnvironmentSlice -Instance $instance
        }
        Get-EnvironmentSlice -Instance $instance
    }
    'Name' {
        if ($Operation -eq 'set') {
            Set-EnvironmentName -Instance $instance
        }
        Get-EnvironmentName -Instance $instance
    }
    'Started' {
        if ($Operation -eq 'set') {
            Set-EnvironmentStarted -Instance $instance -Confirm:$false
        }
        else {
            Get-EnvironmentStarted -Instance $instance
        }
    }
}

if ($Operation -eq 'test') {
    $state['_inDesiredState'] = [bool] $state._exist
}

$state | ConvertTo-Json -Compress -Depth 10
