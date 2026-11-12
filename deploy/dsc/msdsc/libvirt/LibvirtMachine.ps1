#requires -PSEdition Core
#requires -Version 7.7.0
# The Xmip.Libvirt/Machine kind (libvirt.resource.ps1): one machine as a
# libvirt domain, installed unattended from its operating system's ISO, the
# counterpart of the Hyper-V template's machine.
#
# Its disk, its installation image and its answer medium are volumes of the
# environment's pool, so the hypervisor reads them wherever they came from.
# The installation is done when the guest answers at its address; its media
# are then removed and the domain's metadata records it installed, so it is
# never installed again. What each step does is deploy/dsc/machine's
# (LibvirtInstallation.ps1), which Ansible's template asks too; this kind
# says where the machine is and moves it on.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-LibvirtGuestInstalled {
    <#
    .SYNOPSIS
    Whether the guest runs the system on its disk: an AlmaLinux guest
    answers SSH at its address, a Windows guest WinRM. Neither answers while
    its installer runs.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [int] $port = (Get-LibvirtMachinePlan -Instance $Instance).port
    # One second is the least Test-Connection waits.
    return Test-Connection -TargetName $Instance['address'] -TcpPort $port -TimeoutSeconds 1 -Quiet
}

function Get-LibvirtMachineState {
    <#
    .SYNOPSIS
    Where the machine is: NotDefined, NotStarted, Installing, Installed (the
    guest answers, its media are still in) or Done; and whether it runs. A
    machine another technology made is refused.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [hashtable] $record = Get-LibvirtMachineRecord -Instance $Instance
    if (-not $record.defined) {
        return @{ name = $name; installation = 'NotDefined'; running = $false }
    }
    [bool] $running = (Invoke-Virsh -Argument @('domstate', $name)) -match '^running'
    [string] $installation = if ($record.installed) {
        'Done'
    }
    elseif (-not $running) {
        'NotStarted'
    }
    elseif (Test-LibvirtGuestInstalled -Instance $Instance) {
        'Installed'
    }
    else {
        'Installing'
    }
    return @{ name = $name; installation = $installation; running = $running }
}

function Set-LibvirtMachine {
    <#
    .SYNOPSIS
    Moves the machine on: one never defined is started installing, an
    installed one that is off is started from its disk, one whose guest
    answers has its media removed. One still installing is left to it, and
    its state says so: DSC reads what the resource writes as its answer, so
    nothing else is written.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $state = Get-LibvirtMachineState -Instance $Instance
    [string] $step = $state.installation
    if (-not $PSCmdlet.ShouldProcess($Instance['name'], "Move the installation on from $step")) {
        return
    }
    switch ($step) {
        'NotDefined' { Start-LibvirtMachineInstallation -Instance $Instance }
        'NotStarted' { Start-LibvirtMachine -Instance $Instance }
        'Installed' { Complete-LibvirtMachineInstallation -Instance $Instance }
        'Done' {
            if (-not $state.running) {
                Start-LibvirtMachine -Instance $Instance
            }
        }
    }
}
