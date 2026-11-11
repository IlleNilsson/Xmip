#requires -Version 7.7.0

<#
    The Xmip resources of the Hyper-V template (README.md): an environment's
    machines on a Windows host's Hyper-V, as the libvirt template is for a
    host that runs Linux. A resource manifest beside this file names each
    kind, and DSC runs this script with the kind and the operation, the
    instance's properties as JSON on standard input; it answers the
    instance's state as JSON.

    - Network: an internal switch, the host's address on it, the machines'
      gateway, and outbound NAT for the network's prefix.
    - Machine: one machine, a generation 2 VM installed unattended from its
      ISO.

    get and test answer what is not there yet as absent, never as a
    failure. Every rule about a switch, an address, a NAT or a VM is
    Hyper-V's and Windows's; this only asks their commands
    (HyperVResource.ps1).

    Style: doc/governance/powershell-style.md
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Network', 'Machine')]
    [string] $Kind,

    [Parameter(Mandatory = $true)]
    [ValidateSet('get', 'set', 'test')]
    [string] $Operation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path -Path $PSScriptRoot -ChildPath 'HyperVResource.ps1')

[hashtable] $instance = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
Invoke-HyperVResource -Kind $Kind -Operation $Operation -Instance $instance |
    ConvertTo-Json -Compress -Depth 10
