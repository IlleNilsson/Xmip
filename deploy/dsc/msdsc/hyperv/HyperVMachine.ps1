#requires -PSEdition Core
#requires -Version 7.7.0
# The Xmip.HyperV/Machine kind (HyperVResource.ps1): one machine as a
# Hyper-V VM, the counterpart of the libvirt template's machine. Its folder,
# <root>\<name>, holds its new dynamic disk, os.vhdx, made once and never
# resized or replaced, and its answer medium while it installs. The VM is
# generation 2, its hardware the machine's (HyperVHardware.ps1), and it is
# installed unattended from its operating system's ISO
# (HyperVInstallation.ps1). A machine that is not there is found absent,
# never refused.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Hyper-V's MAC prefix: the adapter's static MAC ends in the address's last
# three octets (MachineAnswer.ps1).
$script:HyperVMacPrefix = '00155D'

# Where the VM's drives sit on SCSI controller 0: the disk New-VM attaches
# first, then the two DVD drives.
$script:HyperVDiskLocation = 0
$script:HyperVInstallLocation = 1
$script:HyperVAnswerLocation = 2

function Get-HyperVMachineDisk {
    <#
    .SYNOPSIS
    The machine's disk, os.vhdx in its folder, <root>\<name>.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $directory = Join-Path -Path $Instance['root'] -ChildPath $Instance['name']
    return Join-Path -Path $directory -ChildPath 'os.vhdx'
}

function Get-HyperVVm {
    <#
    .SYNOPSIS
    The VM of the name; nothing where there is none. Every VM is listed and
    the name looked for, so a host refusing the list is an error and a VM
    that is not there is not.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    return (Get-VM | Where-Object { $_.Name -eq $Name })
}

function Get-HyperVMachineState {
    <#
    .SYNOPSIS
    Where the machine is: whether its VM exists (_exist), its installation
    (Absent, NotStarted, Installing, Installed or Done), whether it runs, and
    how it differs from its instance, in words (findings); none once it is
    installed, running and its hardware is as the instance says.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [object] $vm = Get-HyperVVm -Name $name
    if ($null -eq $vm) {
        return @{
            _exist = $false; installation = 'Absent'; running = $false
            findings = @("${name}: absent.")
        }
    }
    [string] $installation = Get-HyperVInstallationState -Instance $Instance -Vm $vm
    [bool] $running = "$($vm.State)" -eq 'Running'
    [string[]] $findings = @(Get-HyperVHardwareFinding -Instance $Instance -Vm $vm)
    if ($installation -ne 'Done' -or -not $running) {
        $findings += "${name}: $installation, running $running."
    }
    return @{
        _exist = $true; installation = $installation; running = $running
        findings = $findings
    }
}

function New-HyperVMachine {
    <#
    .SYNOPSIS
    Makes the machine's folder, its disk where it is not there yet, and a
    generation 2 VM holding it, on the environment's switch, whose own files
    Hyper-V keeps in a folder of its name under the root.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [string] $disk = Get-HyperVMachineDisk -Instance $Instance
    if (-not $PSCmdlet.ShouldProcess($name, 'Make its folder, its disk and its VM')) {
        return
    }
    New-Item -Path (Split-Path -Path $disk -Parent) -ItemType Directory -Force | Out-Null
    if (-not (Test-Path -LiteralPath $disk)) {
        New-VHD -Path $disk -SizeBytes ([long] $Instance['diskGB'] * 1GB) -Dynamic | Out-Null
    }
    [hashtable] $vm = @{
        Name = $name
        Generation = 2
        MemoryStartupBytes = [long] $Instance['memoryGB'] * 1GB
        VHDPath = $disk
        SwitchName = $Instance['network'].name
        Path = $Instance['root']
    }
    New-VM @vm | Out-Null
}

function Set-HyperVMachine {
    <#
    .SYNOPSIS
    Moves the machine on: makes it where it is absent, gives it its
    hardware where it differs, and moves its installation on.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    if (-not $PSCmdlet.ShouldProcess($name, 'Make the machine and move its installation on')) {
        return
    }
    if ($null -eq (Get-HyperVVm -Name $name)) {
        New-HyperVMachine -Instance $Instance
    }
    [object] $vm = Get-HyperVVm -Name $name
    if (@(Get-HyperVHardwareFinding -Instance $Instance -Vm $vm).Count -gt 0) {
        Set-HyperVHardware -Instance $Instance
    }
    Set-HyperVInstallation -Instance $Instance
}
