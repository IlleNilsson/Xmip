#requires -PSEdition Core
#requires -Version 7.7.0
# What a machine is on a Hyper-V host: its folder, <root>\<name>, holding its
# disk, os.vhdx, its answer medium while it installs and the file that says
# it is installed; its static MAC by Hyper-V's prefix; where its drives sit
# on SCSI controller 0; and its answer medium. One home for both
# technologies: Microsoft DSC's Xmip.HyperV resources (deploy/dsc/msdsc/
# hyperv) dot-source it, and Ansible's xmip_machine role asks machine.ps1,
# on a controller that may not be the host, so a path is the host's,
# joined with its separator.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'MachineAnswer.ps1')

# Hyper-V's MAC prefix: the adapter's static MAC ends in the address's last
# three octets (MachineAnswer.ps1).
$script:HyperVMacPrefix = '00155D'
# The package of the guest services on Hyper-V, which the kickstart installs.
$script:HyperVGuestPackage = 'hyperv-daemons'

# Where the VM's drives sit on SCSI controller 0: the disk New-VM attaches
# first, then the two DVD drives.
$script:HyperVDiskLocation = 0
$script:HyperVInstallLocation = 1
$script:HyperVAnswerLocation = 2

function Join-HyperVPath {
    <#
    .SYNOPSIS
    A path of the host's: $Parent and $Child joined with the separator
    $Parent is written with, a Windows host's backslash wherever it is
    asked.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Parent,

        [Parameter(Mandatory = $true)]
        [string] $Child
    )

    if ($Parent -notmatch '^[A-Za-z]:|\\') {
        return Join-Path -Path $Parent -ChildPath $Child
    }
    return $Parent.TrimEnd('\') + '\' + $Child
}

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

    [string] $directory = Join-HyperVPath -Parent $Instance['root'] -Child $Instance['name']
    return Join-HyperVPath -Parent $directory -Child 'os.vhdx'
}

function Get-HyperVMachineFile {
    <#
    .SYNOPSIS
    A file of the machine's folder: answer.iso, its answer medium while it
    installs, or installed, which says it was installed and its media
    removed, so a VM found off later is started from its disk. Delete
    installed, and the disk, to install the machine anew.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [ValidateSet('answer.iso', 'installed')]
        [string] $Name
    )

    [string] $directory = Join-HyperVPath -Parent $Instance['root'] -Child $Instance['name']
    return Join-HyperVPath -Parent $directory -Child $Name
}

function New-HyperVAnswerMedium {
    <#
    .SYNOPSIS
    Writes one machine's answer medium at $Path, as Hyper-V's machines read
    it: its static MAC by Hyper-V's prefix and the guest services in its
    packages.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [hashtable] $asked = @{
        Machine = [pscustomobject] $Instance
        MacAddress = Get-MachineMacAddress -Address $Instance['address'] -Prefix (
            $script:HyperVMacPrefix)
        GuestPackage = $script:HyperVGuestPackage
    }
    if ($PSCmdlet.ShouldProcess($Path, 'Write the answer medium')) {
        [hashtable] $medium = Get-MachineAnswerMedium @asked
        New-MachineAnswerMedium -Path $Path -Medium $medium -Confirm:$false
    }
}

function Get-HyperVMachinePlan {
    <#
    .SYNOPSIS
    Everything a template needs to make one machine on Hyper-V beyond the
    host's own commands: its folder's files, its MAC, the drives' places,
    and the port it answers on once installed.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [bool] $windows = $Instance['image'].family -eq 'Windows'
    return @{
        disk = Get-HyperVMachineDisk -Instance $Instance
        answer = Get-HyperVMachineFile -Instance $Instance -Name 'answer.iso'
        installed = Get-HyperVMachineFile -Instance $Instance -Name 'installed'
        mac = Get-MachineMacAddress -Address $Instance['address'] -Prefix $script:HyperVMacPrefix
        location = @{
            disk = $script:HyperVDiskLocation
            install = $script:HyperVInstallLocation
            answer = $script:HyperVAnswerLocation
        }
        port = if ($windows) { 5985 } else { 22 }
    }
}
