#requires -PSEdition Core
#requires -Version 7.6.5
# A lab VM on the host: created with a new disk of its own, installed from
# its Os's ISO with a generated answer medium, found to differ or not, and
# once its guest answers, its media ejected. Hyper-V calls are guarded at the
# resource boundary, as in LabHost.ps1.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LabMachineDirectory {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    return Join-Path -Path $Lab.Root -ChildPath $Machine.Name
}

function Get-LabVirtualMachineFinding {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [object] $vm = Get-VM -Name $Machine.Name -ErrorAction SilentlyContinue
    if ($null -eq $vm) {
        return "$($Machine.Name): VM is missing."
    }
    [hashtable] $os = $script:LabOs[$Machine.Os]
    [object[]] $nics = @(Get-VMNetworkAdapter -VMName $Machine.Name)
    [object] $memory = Get-VMMemory -VMName $Machine.Name
    [string[]] $disks = @(Get-VMHardDiskDrive -VMName $Machine.Name | ForEach-Object { $_.Path })
    [string] $directory = Get-LabMachineDirectory -Lab $Lab -Machine $Machine
    [string] $disk = Join-Path -Path $directory -ChildPath 'os.vhdx'
    if ($vm.Notes -ne $Lab.LabId -or $vm.Generation -ne 2 -or
        $vm.ProcessorCount -ne $Machine.Cpu -or
        $memory.Startup -ne ($Machine.MemoryGB * 1GB) -or
        $memory.DynamicMemoryEnabled -or $vm.State -ne 'Running' -or
        $nics.Count -ne 1 -or $nics[0].SwitchName -ne $Lab.Network.SwitchName -or
        ($disks -join '|') -ne $disk) {
        Write-Output -InputObject "$($Machine.Name): VM settings differ."
    }
    [string] $mac = Get-LabMacAddress -Address $Machine.Address
    if ($nics.Count -eq 1 -and $nics[0].MacAddress -ne $mac) {
        Write-Output -InputObject "$($Machine.Name): static MAC differs."
    }
    [object] $firmware = Get-VMFirmware -VMName $Machine.Name
    if ($firmware.SecureBoot -ne 'On' -or $firmware.SecureBootTemplate -ne $os.SecureBootTemplate) {
        Write-Output -InputObject "$($Machine.Name): Secure Boot is off or its template differs."
    }
    [object[]] $drives = @($firmware.BootOrder | Where-Object BootType -eq 'Drive')
    if ($drives.Count -eq 0 -or $drives[0].Device.Path -ne $disk) {
        Write-Output -InputObject "$($Machine.Name): boots from another drive before its disk."
    }
    if ($os.Tpm -and -not (Get-VMSecurity -VMName $Machine.Name).TpmEnabled) {
        Write-Output -InputObject "$($Machine.Name): virtual TPM is disabled."
    }
    if (@(Get-LabLoadedDrive -Machine $Machine).Count -gt 0) {
        [string] $installing = 'installing from its ISO; the media are ejected once it answers.'
        Write-Output -InputObject "$($Machine.Name): $installing"
    }
}

function Get-LabLoadedDrive {
    <#
    .SYNOPSIS
    The VM's DVD drives that hold a medium: while it installs, its ISO and
    its answer medium.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    return @(Get-VMDvdDrive -VMName $Machine.Name |
        Where-Object { -not [string]::IsNullOrEmpty($_.Path) })
}

function New-LabAnswerMedium {
    <#
    .SYNOPSIS
    Writes an answer medium as an ISO image (ISO 9660 with Joliet names),
    through the image mastering API every Windows host has: no tool to install.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [hashtable] $Medium
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write the answer medium')) {
        return
    }
    [string] $stage = "$Path.files"
    New-Item -Path $stage -ItemType Directory -Force | Out-Null
    [IO.FileStream] $out = $null
    try {
        [System.Text.UTF8Encoding] $utf8 = [System.Text.UTF8Encoding]::new($false)
        foreach ($name in $Medium.File.Keys) {
            [string] $file = Join-Path -Path $stage -ChildPath $name
            [IO.File]::WriteAllText($file, $Medium.File[$name], $utf8)
        }
        [object] $image = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
        # 1 is ISO 9660 and 2 is Joliet: both read by WinPE and by Anaconda.
        $image.FileSystemsToCreate = 3
        $image.VolumeName = $Medium.Label
        $image.Root.AddTree($stage, $false)
        [object] $result = $image.CreateResultImage()
        [long] $left = [long] $result.TotalBlocks * $result.BlockSize
        # The image is a COM IStream; its Read is reached through the interface.
        [Reflection.MethodInfo] $read =
            [System.Runtime.InteropServices.ComTypes.IStream].GetMethod('Read')
        [byte[]] $buffer = [byte[]]::new(64KB)
        $out = [IO.File]::Create($Path)
        while ($left -gt 0) {
            [int] $count = [Math]::Min($left, $buffer.Length)
            $read.Invoke($result.ImageStream, @($buffer, $count, [IntPtr]::Zero)) | Out-Null
            $out.Write($buffer, 0, $count)
            $left -= $count
        }
    }
    finally {
        if ($null -ne $out) {
            $out.Dispose()
        }
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Ignore
    }
}

function Send-LabBootKey {
    <#
    .SYNOPSIS
    Presses Space in a starting VM's console for its first twenty seconds.
    .DESCRIPTION
    A Windows ISO boots only after "Press any key to boot from CD or DVD",
    and on Hyper-V nobody is there to press one. Its disk comes first in the
    boot order but is empty, so the firmware moves on to the ISO, whose
    prompt waits about five seconds; Space answers it, and pressed before or
    after the prompt does nothing. Once Windows is on the disk, the disk
    boots and the prompt is never shown again.
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

function New-LabVirtualMachine {
    <#
    .SYNOPSIS
    Creates one lab VM: a new disk of lab.json's size, its static MAC, its
    Os's ISO and its answer medium in two DVD drives, the disk first in the
    boot order, its Os's Secure Boot template, and a TPM where its Os needs one.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [hashtable] $Medium
    )

    [hashtable] $os = $script:LabOs[$Machine.Os]
    [string] $directory = Get-LabMachineDirectory -Lab $Lab -Machine $Machine
    [string] $disk = Join-Path -Path $directory -ChildPath 'os.vhdx'
    [string] $answer = Join-Path -Path $directory -ChildPath 'answer.iso'
    if (Test-Path -LiteralPath $directory) {
        throw "REFUSED: unregistered VM directory already exists: $directory"
    }
    New-Item -Path $directory -ItemType Directory | Out-Null
    New-VHD -Path $disk -SizeBytes ($Machine.DiskGB * 1GB) -Dynamic | Out-Null
    New-LabAnswerMedium -Path $answer -Medium $Medium -Confirm:$false
    [hashtable] $create = @{
        Name = $Machine.Name
        Generation = 2
        VHDPath = $disk
        Path = $directory
        MemoryStartupBytes = $Machine.MemoryGB * 1GB
        SwitchName = $Lab.Network.SwitchName
    }
    New-VM @create | Out-Null
    Set-VM -Name $Machine.Name -Notes $Lab.LabId -AutomaticCheckpointsEnabled $false
    Set-VMProcessor -VMName $Machine.Name -Count $Machine.Cpu
    Set-VMMemory -VMName $Machine.Name -DynamicMemoryEnabled $false
    [string] $mac = Get-LabMacAddress -Address $Machine.Address
    Set-VMNetworkAdapter -VMName $Machine.Name -StaticMacAddress $mac
    [string] $image = $Lab.Images[$Machine.Os].Path
    [object] $installDrive = Add-VMDvdDrive -VMName $Machine.Name -Path $image -Passthru
    [object] $answerDrive = Add-VMDvdDrive -VMName $Machine.Name -Path $answer -Passthru
    [hashtable] $firmware = @{
        VMName = $Machine.Name
        EnableSecureBoot = 'On'
        SecureBootTemplate = $os.SecureBootTemplate
        BootOrder = @(
            Get-VMHardDiskDrive -VMName $Machine.Name
            $installDrive
            $answerDrive
            Get-VMNetworkAdapter -VMName $Machine.Name
        )
    }
    Set-VMFirmware @firmware
    if ($os.Tpm) {
        Set-VMKeyProtector -VMName $Machine.Name -NewLocalKeyProtector
        Enable-VMTPM -VMName $Machine.Name
    }
}

function Set-LabVirtualMachine {
    <#
    .SYNOPSIS
    Creates a lab VM installing from its ISO, or starts it.
    .DESCRIPTION
    A Windows VM started while its media are in is given the key its ISO
    asks for. An existing VM's hardware drift is reported, never repaired.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [hashtable] $Medium
    )

    [object] $vm = Get-VM -Name $Machine.Name -ErrorAction SilentlyContinue
    if ($null -ne $vm -and $vm.Notes -ne $Lab.LabId) {
        throw "REFUSED: $($Machine.Name) is not owned by this lab."
    }
    if (-not $PSCmdlet.ShouldProcess($Machine.Name, 'Create or start lab VM')) {
        return
    }
    if ($null -eq $vm) {
        New-LabVirtualMachine -Lab $Lab -Machine $Machine -Medium $Medium
    }
    if ((Get-VM -Name $Machine.Name).State -eq 'Off') {
        Start-VM -Name $Machine.Name | Out-Null
        [bool] $installing = @(Get-LabLoadedDrive -Machine $Machine).Count -gt 0
        if ($Machine.Family -eq 'Windows' -and $installing) {
            Send-LabBootKey -Name $Machine.Name
        }
    }
}

function Complete-LabInstallation {
    <#
    .SYNOPSIS
    Once a guest answers, it runs from its disk: its DVD drives are emptied
    and its answer medium, which holds its encoded password, is deleted.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [object[]] $loaded = @(Get-LabLoadedDrive -Machine $Machine)
    [string] $directory = Get-LabMachineDirectory -Lab $Lab -Machine $Machine
    [string] $answer = Join-Path -Path $directory -ChildPath 'answer.iso'
    [bool] $written = Test-Path -LiteralPath $answer
    if (($loaded.Count -eq 0 -and -not $written) -or
        -not $PSCmdlet.ShouldProcess($Machine.Name, 'Eject the installation media')) {
        return
    }
    foreach ($drive in $loaded) {
        [hashtable] $eject = @{
            VMName = $Machine.Name
            ControllerNumber = $drive.ControllerNumber
            ControllerLocation = $drive.ControllerLocation
            Path = $null
        }
        Set-VMDvdDrive @eject
    }
    if ($written) {
        Remove-Item -LiteralPath $answer -Force
    }
}
