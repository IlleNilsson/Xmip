#requires -PSEdition Core
#requires -Version 7.6.5
# What machine.dsc.yaml's two script resources run, for what HyperVDsc has no
# resource for: the hardware a VM needs before its first start (static MAC,
# Secure Boot template, virtual TPM, boot order), and its installation from
# its ISO (answer medium written, media loaded, VM started, media removed once
# the guest is installed). $Machine is the resource's input.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'MachineAnswer.ps1')

# Where the VM's drives sit on SCSI controller 0: the disk VMHyperV attaches
# first, then the two DVD drives machine.dsc.yaml adds.
$script:DiskLocation = 0
$script:InstallLocation = 1
$script:AnswerLocation = 2

function Get-MachineHardwareFinding {
    <#
    .SYNOPSIS
    How the VM's hardware differs from what the machine needs, in words;
    nothing when it does not.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    [string] $name = $Machine.name
    [string] $mac = Get-MachineMacAddress -Address $Machine.address
    if (@(Get-VMNetworkAdapter -VMName $name).MacAddress -notcontains $mac) {
        Write-Output -InputObject "${name}: its adapter has not the static MAC $mac."
    }
    [object] $firmware = Get-VMFirmware -VMName $name
    if ($firmware.SecureBoot -ne 'On' -or
        $firmware.SecureBootTemplate -ne $Machine.image.secureBootTemplate) {
        Write-Output -InputObject (
            "${name}: Secure Boot is off or not $($Machine.image.secureBootTemplate).")
    }
    [int[]] $order = @($firmware.BootOrder | Where-Object BootType -eq 'Drive' |
        ForEach-Object { $_.Device.ControllerLocation })
    [int[]] $wanted = @($script:DiskLocation, $script:InstallLocation, $script:AnswerLocation)
    if (($order -join ',') -ne ($wanted -join ',')) {
        Write-Output -InputObject "${name}: does not boot its disk first, then its two DVD drives."
    }
    if ($Machine.image.tpm -and -not (Get-VMSecurity -VMName $name).TpmEnabled) {
        Write-Output -InputObject "${name}: its virtual TPM is off."
    }
}

function Set-MachineHardware {
    <#
    .SYNOPSIS
    Gives a VM that is off the hardware its machine needs. A running VM is
    refused, never stopped.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    [string] $name = $Machine.name
    if ((Get-VM -Name $name).State -ne 'Off') {
        throw "REFUSED: ${name} is running; its hardware changes only while it is off."
    }
    if (-not $PSCmdlet.ShouldProcess($name, 'Set the static MAC, firmware and TPM')) {
        return
    }
    [string] $mac = Get-MachineMacAddress -Address $Machine.address
    Set-VMNetworkAdapter -VMName $name -StaticMacAddress $mac
    [object[]] $drives = @(
        Get-VMHardDiskDrive -VMName $name -ControllerLocation $script:DiskLocation
        Get-VMDvdDrive -VMName $name -ControllerLocation $script:InstallLocation
        Get-VMDvdDrive -VMName $name -ControllerLocation $script:AnswerLocation
    )
    [hashtable] $firmware = @{
        VMName = $name
        EnableSecureBoot = 'On'
        SecureBootTemplate = $Machine.image.secureBootTemplate
        BootOrder = @($drives) + @(Get-VMNetworkAdapter -VMName $name)
    }
    Set-VMFirmware @firmware
    if ($Machine.image.tpm -and -not (Get-VMSecurity -VMName $name).TpmEnabled) {
        Set-VMKeyProtector -VMName $name -NewLocalKeyProtector
        Enable-VMTPM -VMName $name
    }
}

function Get-MachineAnswerPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    return Join-Path -Path $Machine.directory -ChildPath 'answer.iso'
}

function Test-MachineGuestInstalled {
    <#
    .SYNOPSIS
    Whether the machine runs the system installed on its disk: a Windows
    guest opens PowerShell Direct as its Administrator, an AlmaLinux guest
    answers SSH at its address. Neither answers while its installer runs.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    if ((Get-VM -Name $Machine.name).State -ne 'Running') {
        return $false
    }
    if ($Machine.image.family -eq 'Windows') {
        [hashtable] $direct = @{
            VMName = $Machine.name
            Credential = Import-Clixml -LiteralPath $Machine.credentialPath
            ScriptBlock = { $true }
            ErrorAction = 'SilentlyContinue'
        }
        return [bool] (Invoke-Command @direct)
    }
    # One second is the least Test-Connection waits.
    return Test-Connection -TargetName $Machine.address -TcpPort 22 -TimeoutSeconds 1 -Quiet
}

function Get-MachineLoadedDrive {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    return @(Get-VMDvdDrive -VMName $Machine.name |
        Where-Object { -not [string]::IsNullOrEmpty($_.Path) })
}

function Get-MachineInstalledPath {
    <#
    .SYNOPSIS
    The file that says the machine was installed and its media removed, so a
    VM found off later is started from its disk, never installed again.
    Delete it, and the disk, to install the machine anew.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    return Join-Path -Path $Machine.directory -ChildPath 'installed'
}

function Get-MachineInstallationState {
    <#
    .SYNOPSIS
    Where the machine is in its installation: NotStarted, Installing,
    Installed (the guest answers, its media are still in) or Done.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    if (Test-Path -LiteralPath (Get-MachineInstalledPath -Machine $Machine)) {
        return 'Done'
    }
    if ((Get-VM -Name $Machine.name).State -eq 'Off') {
        return 'NotStarted'
    }
    if (Test-MachineGuestInstalled -Machine $Machine) {
        return 'Installed'
    }
    return 'Installing'
}

function Start-MachineInstallation {
    <#
    .SYNOPSIS
    Checks the ISO against its SHA-256, writes the answer medium, loads both
    into the VM's DVD drives and starts it.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    [string] $iso = $Machine.image.path
    [string] $hash = (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash
    if ($hash -ne $Machine.image.sha256) {
        throw "REFUSED: $iso has SHA-256 $hash, not $($Machine.image.sha256)."
    }
    [string] $answer = Get-MachineAnswerPath -Machine $Machine
    [hashtable] $medium = Get-MachineAnswerMedium -Machine $Machine
    New-MachineAnswerMedium -Path $answer -Medium $medium -Confirm:$false
    [string] $name = $Machine.name
    [hashtable] $drive = @{ VMName = $name; ControllerNumber = 0 }
    Set-VMDvdDrive @drive -ControllerLocation $script:InstallLocation -Path $iso
    Set-VMDvdDrive @drive -ControllerLocation $script:AnswerLocation -Path $answer
    Start-VM -Name $name
    if ($Machine.image.family -eq 'Windows') {
        Send-MachineBootKey -Name $name
    }
}

function Send-MachineBootKey {
    <#
    .SYNOPSIS
    Presses Space in a starting VM's console for its first twenty seconds.
    .DESCRIPTION
    A Windows ISO boots only after "Press any key to boot from CD or DVD",
    and on Hyper-V nobody is there to press one. The empty disk comes first
    in the boot order, so the firmware moves on to the ISO, whose prompt
    waits about five seconds; Space answers it. Once Windows is on the disk,
    the disk boots and the prompt is never shown again.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    [hashtable] $query = @{
        Namespace = 'root/virtualization/v2'
        ClassName = 'Msvm_ComputerSystem'
        Filter = "ElementName = '$Name'"
    }
    [object] $system = Get-CimInstance @query
    [object] $keyboard = Get-CimAssociatedInstance -InputObject $system -ResultClassName (
        'Msvm_Keyboard')
    [datetime] $until = [datetime]::UtcNow.AddSeconds(20)
    while ([datetime]::UtcNow -lt $until) {
        [hashtable] $press = @{
            InputObject = $keyboard
            MethodName = 'TypeKey'
            Arguments = @{ keyCode = [uint32] 0x20 }
        }
        Invoke-CimMethod @press | Out-Null
        Start-Sleep -Milliseconds 500
    }
}

function Complete-MachineInstallation {
    <#
    .SYNOPSIS
    Empties the VM's DVD drives, deletes the answer medium, which holds the
    encoded Administrator password, and records the machine installed.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    foreach ($drive in @(Get-MachineLoadedDrive -Machine $Machine)) {
        [hashtable] $eject = @{
            VMName = $Machine.name
            ControllerNumber = $drive.ControllerNumber
            ControllerLocation = $drive.ControllerLocation
            Path = $null
        }
        Set-VMDvdDrive @eject
    }
    Remove-Item -LiteralPath (Get-MachineAnswerPath -Machine $Machine) -Force -ErrorAction Ignore
    New-Item -Path (Get-MachineInstalledPath -Machine $Machine) -ItemType File -Force | Out-Null
}

function Set-MachineInstallation {
    <#
    .SYNOPSIS
    Moves the installation on: an installed machine that is off is started
    from its disk, one never installed is started installing, one whose
    guest answers has its media removed. One still installing is left to it.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    [string] $state = Get-MachineInstallationState -Machine $Machine
    if (-not $PSCmdlet.ShouldProcess($Machine.name, "Move the installation on from $state")) {
        return
    }
    switch ($state) {
        'Done' {
            if ((Get-VM -Name $Machine.name).State -eq 'Off') {
                Start-VM -Name $Machine.name
            }
        }
        'NotStarted' { Start-MachineInstallation -Machine $Machine }
        'Installed' { Complete-MachineInstallation -Machine $Machine }
        'Installing' {
            Write-Warning -Message (
                "$($Machine.name): installing from its ISO; run set again once it has.")
        }
    }
}

function Test-MachineInstallation {
    <#
    .SYNOPSIS
    True when the machine is installed, its media removed, and it runs.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    return (Get-MachineInstallationState -Machine $Machine) -eq 'Done' -and
        (Get-VM -Name $Machine.name).State -eq 'Running'
}
