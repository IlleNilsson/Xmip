#requires -PSEdition Core
#requires -Version 7.7.0
# The hardware of an Xmip.HyperV/Machine's VM (HyperVMachine.ps1): its
# settings (its memory, static, or dynamic between the least and the most
# its machine names, its processors, no automatic checkpoints, the
# environment's name in its notes), its devices (the machine's disk at
# SCSI 0:0, one adapter on the environment's switch with a static MAC made
# from its address, and a gateway machine a second, Uplink, on the uplink,
# two DVD drives) and its firmware (Secure Boot with the template its image
# names, the disk booted first, then the two drives, then its own adapter,
# never the uplink's, and a virtual TPM where its image asks for one). It
# changes only while the VM is off; the disk is never replaced and an
# adapter never removed.
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

    [Collections.IDictionary] $dynamic = Get-MachineDynamicMemory -Instance $Instance
    [Collections.Specialized.OrderedDictionary] $setting = [ordered] @{
        ProcessorCount = [long] $Instance['cpu']
        MemoryStartup = [long] $Instance['memoryGB'] * 1GB
        DynamicMemoryEnabled = $dynamic.Count -gt 0
    }
    if ($dynamic.Count -gt 0) {
        $setting['MemoryMinimum'] = [long] $dynamic['minimumMB'] * 1MB
        $setting['MemoryMaximum'] = [long] $dynamic['maximumMB'] * 1MB
    }
    $setting['AutomaticCheckpointsEnabled'] = $false
    $setting['Notes'] = [string] $Instance['environment']
    return $setting
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
    Get-HyperVAdapterFinding -Instance $Instance -Vm $Vm
    [int[]] $dvd = @($Vm.DVDDrives | Where-Object { $_.ControllerNumber -eq 0 } |
        ForEach-Object { $_.ControllerLocation } | Sort-Object)
    if (($dvd -join ',') -ne "$script:HyperVInstallLocation,$script:HyperVAnswerLocation") {
        Write-Output -InputObject "${name}: has not its two DVD drives at SCSI 0:1 and 0:2."
    }
}

function Get-HyperVAdapterPlan {
    <#
    .SYNOPSIS
    The adapters the machine needs, each its switch, its static MAC and the
    VM's adapters it is held by: Own, on the environment's switch, and
    Uplink, a gateway machine's second, on the uplink, whose switch is
    empty where the machine is none.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [object] $Vm
    )

    [hashtable] $mac = @{ Address = $Instance['address']; Prefix = $script:HyperVMacPrefix }
    [object[]] $adapters = @($Vm.NetworkAdapters)
    return @{
        Own = @{ Switch = $Instance['network']['name']; Mac = Get-MachineMacAddress @mac
            Held = @($adapters | Where-Object { $_.Name -ne $script:HyperVUplinkAdapter }) }
        Uplink = @{ Switch = [string] $Instance['network']['uplink']
            Mac = Get-MachineMacAddress @mac -Uplink
            Held = @($adapters | Where-Object { $_.Name -eq $script:HyperVUplinkAdapter }) }
    }
}

function Get-HyperVAdapterFinding {
    <#
    .SYNOPSIS
    How the VM's adapters differ from the machine's: its own on the switch
    with its static MAC, and a gateway machine's Uplink on the uplink with
    its own; an Uplink on a machine that is no gateway.
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
    [hashtable] $plan = Get-HyperVAdapterPlan -Instance $Instance -Vm $Vm
    foreach ($side in @(@{ Plan = $plan.Own; Said = 'one adapter' }
            @{ Plan = $plan.Uplink; Said = "one adapter $script:HyperVUplinkAdapter" })) {
        [object[]] $held = $side.Plan.Held
        if (-not $side.Plan.Switch) {
            if ($held.Count -gt 0) {
                Write-Output -InputObject "${name}: has an adapter $script:HyperVUplinkAdapter."
            }
            continue
        }
        if ($held.Count -ne 1 -or $held[0].SwitchName -ne $side.Plan.Switch -or
            $held[0].MacAddress -ne $side.Plan.Mac) {
            Write-Output -InputObject ("${name}: has not $($side.Said), on " +
                "$($side.Plan.Switch), with the MAC $($side.Plan.Mac).")
        }
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
    more than one adapter of its own, which would give each the machine's
    MAC, or an Uplink it is not given: an adapter is never removed.
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
    [hashtable] $plan = Get-HyperVAdapterPlan -Instance $Instance -Vm $vm
    [int] $uplink = $plan.Uplink.Held.Count
    [bool] $unasked = $uplink -gt 0 -and -not $plan.Uplink.Switch
    if ($plan.Own.Held.Count -gt 1 -or $uplink -gt 1 -or $unasked) {
        [string] $wanted = if ($plan.Uplink.Switch) { "one and one $script:HyperVUplinkAdapter" }
        else { 'one' }
        throw ("REFUSED: ${name} has $(@($vm.NetworkAdapters).Count) adapters, not $wanted; " +
            'an adapter is never removed.')
    }
    if (-not $PSCmdlet.ShouldProcess($name, 'Set its settings, devices and firmware')) {
        return
    }
    [Collections.IDictionary] $want = Get-HyperVMachineSetting -Instance $Instance
    [hashtable] $setting = @{
        Name = $name
        ProcessorCount = $want.ProcessorCount
        MemoryStartupBytes = $want.MemoryStartup
        AutomaticCheckpointsEnabled = $want.AutomaticCheckpointsEnabled
        Notes = $want.Notes
    }
    if ($want.DynamicMemoryEnabled) {
        $setting['DynamicMemory'] = $true
        $setting['MemoryMinimumBytes'] = $want.MemoryMinimum
        $setting['MemoryMaximumBytes'] = $want.MemoryMaximum
    }
    else {
        $setting['StaticMemory'] = $true
    }
    Set-VM @setting
    Set-HyperVDevice -Instance $Instance -Vm $vm
    Set-HyperVFirmware -Instance $Instance
}

function Set-HyperVDevice {
    <#
    .SYNOPSIS
    Gives the VM its one adapter on the switch with its static MAC, a
    gateway machine its Uplink on the uplink with its own, each by its name,
    and its two DVD drives where they are missing.
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
    [hashtable] $plan = Get-HyperVAdapterPlan -Instance $Instance -Vm $Vm
    # The name New-VM and Add-VMNetworkAdapter give an adapter named none.
    [hashtable] $own = $plan.Own
    $own['Name'] = if ($own.Held.Count -gt 0) { $own.Held[0].Name } else { 'Network Adapter' }
    [hashtable] $uplink = $plan.Uplink
    $uplink['Name'] = $script:HyperVUplinkAdapter
    foreach ($side in @($own, $uplink | Where-Object { $_.Switch })) {
        [hashtable] $adapter = @{ VMName = $name; Name = $side.Name }
        if ($side.Held.Count -eq 0) {
            Add-VMNetworkAdapter @adapter -SwitchName $side.Switch
        }
        Connect-VMNetworkAdapter @adapter -SwitchName $side.Switch
        Set-VMNetworkAdapter @adapter -StaticMacAddress $side.Mac
    }
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
    then the two DVD drives, then the network, never the uplink, and turns
    on the virtual TPM where the image asks for one.
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
        Get-VMNetworkAdapter -VMName $name | Where-Object {
            $_.Name -ne $script:HyperVUplinkAdapter }
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
