#requires -PSEdition Core
#requires -Version 7.7.0
# The hardware of an Xmip.HyperV/Machine's VM (HyperVMachine.ps1): its
# settings (static memory, its processors, no automatic checkpoints, the
# environment's name in its notes), its devices (the machine's disk at
# SCSI 0:0, one adapter on the environment's switch with a static MAC made
# from its address, two DVD drives) and its firmware (Secure Boot with the
# template its image names, the disk booted first, then the two drives, and
# a virtual TPM where its image asks for one). It changes only while the VM
# is off; the disk is never replaced and an adapter never removed.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-HyperVMachineSetting {
    <#
    .SYNOPSIS
    The VM's settings the instance decides, by the names Get-VM gives them.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    return [ordered] @{
        ProcessorCount = [long] $Instance['cpu']
        MemoryStartup = [long] $Instance['memoryGB'] * 1GB
        DynamicMemoryEnabled = $false
        AutomaticCheckpointsEnabled = $false
        Notes = [string] $Instance['environment']
    }
}

function Get-HyperVHardwareFinding {
    <#
    .SYNOPSIS
    How the VM's hardware differs from what the machine needs, in words:
    its settings, its devices and its firmware; nothing when it does not.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [object] $Vm
    )

    [string] $name = $Instance['name']
    [Collections.IDictionary] $want = Get-HyperVMachineSetting -Instance $Instance
    [string[]] $finding = @(
        foreach ($key in $want.Keys) {
            if ("$($Vm.$key)" -ne "$($want[$key])") {
                "${name}: its $key is $($Vm.$key), not $($want[$key])."
            }
        }
        Get-HyperVDeviceFinding -Instance $Instance -Vm $Vm
        Get-HyperVFirmwareFinding -Instance $Instance
    )
    return $finding
}

function Test-HyperVMachineDisk {
    <#
    .SYNOPSIS
    Whether the VM holds the machine's disk at SCSI 0:0.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [object] $Vm
    )

    [string] $disk = Get-HyperVMachineDisk -Instance $Instance
    return @($Vm.HardDrives | Where-Object {
        $_.ControllerNumber -eq 0 -and
            $_.ControllerLocation -eq $script:HyperVDiskLocation -and $_.Path -eq $disk
    }).Count -eq 1
}

function Get-HyperVDeviceFinding {
    <#
    .SYNOPSIS
    How the VM's disk, adapter and DVD drives differ from the machine's.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [object] $Vm
    )

    [string] $name = $Instance['name']
    if (-not (Test-HyperVMachineDisk -Instance $Instance -Vm $Vm)) {
        Write-Output -InputObject (
            "${name}: does not hold $(Get-HyperVMachineDisk -Instance $Instance) at SCSI 0:0.")
    }
    [string] $switch = $Instance['network'].name
    [string] $mac = Get-MachineMacAddress -Address $Instance['address'] -Prefix (
        $script:HyperVMacPrefix)
    [object[]] $adapters = @($Vm.NetworkAdapters)
    if ($adapters.Count -ne 1 -or $adapters[0].SwitchName -ne $switch -or
        $adapters[0].MacAddress -ne $mac) {
        Write-Output -InputObject "${name}: has not one adapter, on $switch, with the MAC $mac."
    }
    [int[]] $dvd = @($Vm.DVDDrives | Where-Object { $_.ControllerNumber -eq 0 } |
        ForEach-Object { $_.ControllerLocation } | Sort-Object)
    if (($dvd -join ',') -ne "$script:HyperVInstallLocation,$script:HyperVAnswerLocation") {
        Write-Output -InputObject "${name}: has not its two DVD drives at SCSI 0:1 and 0:2."
    }
}

function Get-HyperVFirmwareFinding {
    <#
    .SYNOPSIS
    How the VM's firmware differs from the machine's: Secure Boot and its
    template, the boot order (disk, then the two DVD drives) and the TPM.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [object] $image = $Instance['image']
    [object] $firmware = Get-VMFirmware -VMName $name
    if ("$($firmware.SecureBoot)" -ne 'On' -or
        $firmware.SecureBootTemplate -ne $image.secureBootTemplate) {
        Write-Output -InputObject "${name}: Secure Boot is off or not $($image.secureBootTemplate)."
    }
    [int[]] $order = @($firmware.BootOrder | Where-Object { "$($_.BootType)" -eq 'Drive' } |
        ForEach-Object { $_.Device.ControllerLocation })
    [int[]] $wanted = @($script:HyperVDiskLocation, $script:HyperVInstallLocation,
        $script:HyperVAnswerLocation)
    if (($order -join ',') -ne ($wanted -join ',')) {
        Write-Output -InputObject "${name}: does not boot its disk first, then its DVD drives."
    }
    if ($image.tpm -and -not (Get-VMSecurity -VMName $name).TpmEnabled) {
        Write-Output -InputObject "${name}: its virtual TPM is off."
    }
}

function Set-HyperVHardware {
    <#
    .SYNOPSIS
    Gives a VM that is off the settings, devices and firmware its machine
    needs. A VM that is not off is refused, never stopped; so is one that
    does not hold the machine's disk, which is never replaced, and one with
    more than one adapter, which would give each the machine's MAC: an
    adapter is never removed.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [object] $vm = Get-HyperVVm -Name $name
    if ("$($vm.State)" -ne 'Off') {
        throw "REFUSED: ${name} is $($vm.State); its hardware changes only while it is off."
    }
    if (-not (Test-HyperVMachineDisk -Instance $Instance -Vm $vm)) {
        throw "REFUSED: ${name} does not hold its disk at SCSI 0:0; a disk is never replaced."
    }
    [int] $adapters = @($vm.NetworkAdapters).Count
    if ($adapters -gt 1) {
        throw "REFUSED: ${name} has $adapters adapters, not one; an adapter is never removed."
    }
    if (-not $PSCmdlet.ShouldProcess($name, 'Set its settings, devices and firmware')) {
        return
    }
    [Collections.IDictionary] $want = Get-HyperVMachineSetting -Instance $Instance
    [hashtable] $setting = @{
        Name = $name
        ProcessorCount = $want.ProcessorCount
        StaticMemory = $true
        MemoryStartupBytes = $want.MemoryStartup
        AutomaticCheckpointsEnabled = $want.AutomaticCheckpointsEnabled
        Notes = $want.Notes
    }
    Set-VM @setting
    Set-HyperVDevice -Instance $Instance -Vm $vm
    Set-HyperVFirmware -Instance $Instance
}

function Set-HyperVDevice {
    <#
    .SYNOPSIS
    Gives the VM its one adapter on the switch with its static MAC, and its
    two DVD drives where they are missing.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [object] $Vm
    )

    [string] $name = $Instance['name']
    [string] $switch = $Instance['network'].name
    if (@($Vm.NetworkAdapters).Count -eq 0) {
        Add-VMNetworkAdapter -VMName $name -SwitchName $switch
    }
    Connect-VMNetworkAdapter -VMName $name -SwitchName $switch
    [string] $mac = Get-MachineMacAddress -Address $Instance['address'] -Prefix (
        $script:HyperVMacPrefix)
    Set-VMNetworkAdapter -VMName $name -StaticMacAddress $mac
    foreach ($location in $script:HyperVInstallLocation, $script:HyperVAnswerLocation) {
        if (@($Vm.DVDDrives | Where-Object {
            $_.ControllerNumber -eq 0 -and $_.ControllerLocation -eq $location
        }).Count -eq 0) {
            Add-VMDvdDrive -VMName $name -ControllerNumber 0 -ControllerLocation $location
        }
    }
}

function Set-HyperVFirmware {
    <#
    .SYNOPSIS
    Turns Secure Boot on with the image's template, boots the disk first,
    then the two DVD drives, then the network, and turns on the virtual TPM
    where the image asks for one.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [hashtable] $controller = @{ VMName = $name; ControllerNumber = 0 }
    [object[]] $order = @(
        Get-VMHardDiskDrive @controller -ControllerLocation $script:HyperVDiskLocation
        Get-VMDvdDrive @controller -ControllerLocation $script:HyperVInstallLocation
        Get-VMDvdDrive @controller -ControllerLocation $script:HyperVAnswerLocation
        Get-VMNetworkAdapter -VMName $name
    )
    [hashtable] $firmware = @{
        VMName = $name
        EnableSecureBoot = 'On'
        SecureBootTemplate = $Instance['image'].secureBootTemplate
        BootOrder = $order
    }
    Set-VMFirmware @firmware
    if ($Instance['image'].tpm -and -not (Get-VMSecurity -VMName $name).TpmEnabled) {
        Set-VMKeyProtector -VMName $name -NewLocalKeyProtector
        Enable-VMTPM -VMName $name
    }
}
