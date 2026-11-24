#requires -PSEdition Core
#requires -Version 7.7.0
# The installation of an Xmip.HyperV/Machine (HyperVMachine.ps1) from its
# ISO: the answer medium written into the machine's folder, the ISO and it
# loaded into the VM's two DVD drives, the VM started, and once the guest
# answers from its disk both drives emptied, the medium deleted and the
# machine recorded installed, so it is never installed again.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-HyperVGuestInstalled {
    <#
    .SYNOPSIS
    Whether the guest runs the system installed on its disk: a Windows
    guest opens PowerShell Direct as its Administrator, an AlmaLinux guest
    answers SSH at its address. Neither answers while its installer runs.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if ($Instance['image'].family -eq 'Windows') {
        [hashtable] $direct = @{
            VMName = $Instance['name']
            Credential = Import-Clixml -LiteralPath $Instance['secretPath']
            ScriptBlock = { $true }
            ErrorAction = 'SilentlyContinue'
        }
        return [bool] (Invoke-Command @direct)
    }
    # One second is the least Test-Connection waits.
    [hashtable] $ssh = @{ TargetName = $Instance['address']; TcpPort = 22; TimeoutSeconds = 1 }
    return Test-Connection @ssh -Quiet
}

function Get-HyperVInstallationState {
    <#
    .SYNOPSIS
    Where the machine's VM is in its installation: NotStarted (off, never
    installed), Installing, Installed (the guest answers, its media are
    still in) or Done.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [object] $Vm
    )

    if (Test-Path -LiteralPath (Get-HyperVMachineFile -Instance $Instance -Name 'installed')) {
        return 'Done'
    }
    if ("$($Vm.State)" -eq 'Off') {
        return 'NotStarted'
    }
    if (Test-HyperVGuestInstalled -Instance $Instance) {
        return 'Installed'
    }
    return 'Installing'
}

function Start-HyperVInstallation {
    <#
    .SYNOPSIS
    Checks the ISO against its SHA-256, writes the answer medium, loads both
    into the VM's DVD drives and starts it.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $iso = $Instance['image'].path
    [string] $hash = (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash
    if ($hash -ne $Instance['image'].sha256) {
        throw "REFUSED: $iso has SHA-256 $hash, not $($Instance['image'].sha256)."
    }
    [string] $answer = Get-HyperVMachineFile -Instance $Instance -Name 'answer.iso'
    New-HyperVAnswerMedium -Instance $Instance -Path $answer -Confirm:$false
    [string] $name = $Instance['name']
    [hashtable] $drive = @{ VMName = $name; ControllerNumber = 0 }
    Set-VMDvdDrive @drive -ControllerLocation $script:HyperVInstallLocation -Path $iso
    Set-VMDvdDrive @drive -ControllerLocation $script:HyperVAnswerLocation -Path $answer
    Start-VM -Name $name
    # Enter at the ISO's boot prompt: deploy/dsc/machine/HyperVBootKey.ps1,
    # which Ansible's role runs on the host too.
    if ($Instance['image'].family -eq 'Windows') {
        Send-HyperVBootKey -Name $name
    }
}

function Complete-HyperVInstallation {
    <#
    .SYNOPSIS
    Empties the VM's DVD drives, deletes the answer medium, which holds the
    encoded Administrator password or the key, and records the machine
    installed.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [object[]] $loaded = @(Get-VMDvdDrive -VMName $Instance['name'] |
        Where-Object { -not [string]::IsNullOrEmpty($_.Path) })
    foreach ($drive in $loaded) {
        [hashtable] $eject = @{
            VMName = $Instance['name']
            ControllerNumber = $drive.ControllerNumber
            ControllerLocation = $drive.ControllerLocation
            Path = $null
        }
        Set-VMDvdDrive @eject
    }
    [string] $answer = Get-HyperVMachineFile -Instance $Instance -Name 'answer.iso'
    Remove-Item -LiteralPath $answer -Force -ErrorAction Ignore
    [string] $installed = Get-HyperVMachineFile -Instance $Instance -Name 'installed'
    New-Item -Path $installed -ItemType File -Force | Out-Null
}

function Set-HyperVInstallation {
    <#
    .SYNOPSIS
    Moves the installation on: a VM never installed is started installing,
    one whose guest answers has its media removed, an installed one that is
    off is started from its disk. One still installing is left to it, and
    its state says so: DSC reads what the resource writes as its answer, so
    nothing else is written.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [object] $vm = Get-HyperVVm -Name $name
    [string] $state = Get-HyperVInstallationState -Instance $Instance -Vm $vm
    if (-not $PSCmdlet.ShouldProcess($name, "Move the installation on from $state")) {
        return
    }
    switch ($state) {
        'NotStarted' { Start-HyperVInstallation -Instance $Instance }
        'Installed' { Complete-HyperVInstallation -Instance $Instance }
        'Done' {
            if ("$($vm.State)" -eq 'Off') {
                Start-VM -Name $name
            }
        }
    }
}
