#requires -PSEdition Core
#requires -Version 7.7.0

<#
    What a machine is, and on libvirt each step of its installation, for a
    template that runs no PowerShell resource of its own: Ansible's
    xmip_machine role (deploy/dsc/ansible) asks here, as Microsoft DSC's
    resources dot-source the same files, so a network, a pool, a domain, an
    answer medium or an installing step is written once. The instance is
    JSON on standard input, with the property names DSC's documents give,
    and the answer is on standard output.

    - Network: libvirt's network definition.
    - Pool: libvirt's pool definition.
    - Machine: one machine's plan, JSON: on libvirt its domain's definition,
      its volumes, its DVD drives and the record that says it is installed;
      on Hyper-V its folder's files, its MAC and its drives' places; on both
      the port it answers on once installed.
    - Answer: the machine's answer medium, an ISO written at -Path.
    - State: on libvirt, JSON: whether the machine's domain is defined and
      its record says it is installed, refused where another technology
      made it.
    - Install: on libvirt, its media put in the pool whole, its domain
      defined and started, whatever of that is not done yet.
    - Complete: on libvirt, its media taken out, its answer medium deleted
      and its record written, refused where either is left.

    Style: doc/governance/powershell-style.md
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('libvirt', 'hyperv')]
    [string] $Hypervisor,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Network', 'Pool', 'Machine', 'Answer', 'State', 'Install', 'Complete')]
    [string] $Kind,

    [Parameter()]
    [string] $Path = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($part in 'LibvirtInstallation.ps1', 'HyperVDefinition.ps1') {
    . (Join-Path -Path $PSScriptRoot -ChildPath $part)
}

[hashtable] $instance = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
[bool] $libvirt = $Hypervisor -eq 'libvirt'

if ($Kind -in 'Network', 'Pool', 'State', 'Install', 'Complete' -and -not $libvirt) {
    throw "REFUSED: -Kind $Kind is libvirt's; Hyper-V's are made by its own commands."
}
if ($Kind -eq 'Answer' -and -not $Path) {
    throw 'REFUSED: -Kind Answer writes the answer medium at -Path.'
}

switch ($Kind) {
    'Network' {
        Get-LibvirtNetworkDefinition -Instance $instance
    }
    'Pool' {
        Get-LibvirtPoolDefinition -Instance $instance
    }
    'Machine' {
        [hashtable] $plan = if ($libvirt) { Get-LibvirtMachinePlan -Instance $instance }
        else { Get-HyperVMachinePlan -Instance $instance }
        $plan | ConvertTo-Json -Compress -Depth 5
    }
    'Answer' {
        if ($libvirt) {
            New-LibvirtAnswerMedium -Instance $instance -Path $Path -Confirm:$false
        }
        else {
            New-HyperVAnswerMedium -Instance $instance -Path $Path -Confirm:$false
        }
    }
    'State' {
        Get-LibvirtMachineRecord -Instance $instance | ConvertTo-Json -Compress
    }
    'Install' {
        Start-LibvirtMachineInstallation -Instance $instance
    }
    'Complete' {
        Complete-LibvirtMachineInstallation -Instance $instance
    }
}
