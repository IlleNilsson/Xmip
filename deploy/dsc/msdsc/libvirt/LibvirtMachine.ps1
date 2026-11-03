#requires -PSEdition Core
#requires -Version 7.7.0
# The Xmip.Libvirt/Machine kind (libvirt.resource.ps1): one machine as a
# libvirt domain, installed unattended from its operating system's ISO, the
# counterpart of the Hyper-V template's machine.
#
# Its disk, its installation image and its answer medium are volumes of the
# environment's pool, so the hypervisor reads them wherever they came from.
# The domain boots its disk first, then the DVD: the empty disk does not
# boot, so the firmware moves on to the ISO, which installs onto the disk,
# and every later boot starts from the disk. The installation is done when
# the guest answers at its address; its media are then removed and the
# domain's metadata records it installed, so it is never installed again.
# A TPM is given wherever the host has one to give, never required.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The namespace of the machine's own record in its domain's metadata.
$script:LibvirtMetadata = 'urn:xmip:machine'
# The DVD drives' targets on the SATA bus; the disk is vda or sda before them.
$script:LibvirtInstallTarget = 'sdb'
$script:LibvirtAnswerTarget = 'sdc'

function Get-LibvirtVolumeName {
    <#
    .SYNOPSIS
    The pool volume names of one machine: its disk, its answer medium, and
    its image, named by its SHA-256 so machines of one image share it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    return @{
        Disk = "$($Instance['name']).qcow2"
        Answer = "$($Instance['name'])-answer.iso"
        Image = "image-$($Instance['image'].sha256.Substring(0, 16).ToLowerInvariant()).iso"
    }
}

function Test-LibvirtWindows {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    return $Instance['image'].family -eq 'Windows'
}

function Get-LibvirtMachineDefinition {
    <#
    .SYNOPSIS
    The machine's domain as libvirt reads it. A Windows guest is given the
    SATA disk and e1000e adapter its installer has drivers for; an AlmaLinux
    guest virtio and the guest agent's channel.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $volume = Get-LibvirtVolumeName -Instance $Instance
    [bool] $windows = Test-LibvirtWindows -Instance $Instance
    [string] $pool = ConvertTo-LibvirtText -Value $Instance['pool']
    [string] $disk = if ($windows) { "dev='sda' bus='sata'" } else { "dev='vda' bus='virtio'" }
    [string] $model = if ($windows) { 'e1000e' } else { 'virtio' }
    [string] $mac = Get-LibvirtMacAddress -Address $Instance['address']
    [string[]] $tpm = @()
    if ($null -ne (Get-Command -Name swtpm -ErrorAction SilentlyContinue)) {
        $tpm = @("    <tpm model='tpm-crb'><backend type='emulator' version='2.0'/></tpm>")
    }
    [string[]] $agent = @()
    if (-not $windows) {
        $agent = @("    <channel type='unix'><target type='virtio' " +
            "name='org.qemu.guest_agent.0'/></channel>")
    }
    return @(
        "<domain type='kvm'>"
        "  <name>$(ConvertTo-LibvirtText -Value $Instance['name'])</name>"
        "  <description>$(ConvertTo-LibvirtText -Value $Instance['environment'])</description>"
        "  <memory unit='GiB'>$($Instance['memoryGB'])</memory>"
        "  <vcpu>$($Instance['cpu'])</vcpu>"
        "  <os firmware='efi'>"
        "    <type arch='x86_64' machine='q35'>hvm</type>"
        '    <firmware>'
        "      <feature enabled='yes' name='secure-boot'/>"
        "      <feature enabled='yes' name='enrolled-keys'/>"
        '    </firmware>'
        "    <boot dev='hd'/>"
        "    <boot dev='cdrom'/>"
        '  </os>'
        "  <features><acpi/><apic/><smm state='on'/></features>"
        "  <cpu mode='host-passthrough'/>"
        "  <clock offset='utc'/>"
        '  <devices>'
        "    <disk type='volume' device='disk'><driver name='qemu' type='qcow2'/>"
        "      <source pool='$pool' volume='$($volume.Disk)'/><target $disk/></disk>"
        "    <disk type='volume' device='cdrom'><driver name='qemu' type='raw'/>"
        "      <source pool='$pool' volume='$($volume.Image)'/>"
        "      <target dev='$script:LibvirtInstallTarget' bus='sata'/><readonly/></disk>"
        "    <disk type='volume' device='cdrom'><driver name='qemu' type='raw'/>"
        "      <source pool='$pool' volume='$($volume.Answer)'/>"
        "      <target dev='$script:LibvirtAnswerTarget' bus='sata'/><readonly/></disk>"
        "    <interface type='network'>"
        "      <source network='$(ConvertTo-LibvirtText -Value $Instance['network'].name)'/>"
        "      <mac address='$mac'/><model type='$model'/></interface>"
        "    <serial type='pty'/><console type='pty'/>"
        "    <graphics type='vnc' listen='127.0.0.1'/>"
        "    <video><model type='virtio'/></video>"
        $agent
        $tpm
        '  </devices>'
        '</domain>'
    ) -join "`n"
}

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

    [int] $port = if (Test-LibvirtWindows -Instance $Instance) { 5985 } else { 22 }
    # One second is the least Test-Connection waits.
    return Test-Connection -TargetName $Instance['address'] -TcpPort $port -TimeoutSeconds 1 -Quiet
}

function Get-LibvirtMachineState {
    <#
    .SYNOPSIS
    Where the machine is: NotDefined, NotStarted, Installing, Installed (the
    guest answers, its media are still in) or Done; and whether it runs.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [string] $info = Invoke-Virsh -Argument @('dominfo', $name) -Quiet
    if ([string]::IsNullOrEmpty($info)) {
        return @{ name = $name; installation = 'NotDefined'; running = $false }
    }
    [bool] $running = $info -match '(?m)^State:\s+running'
    [string] $record = Invoke-Virsh -Argument @(
        'metadata', $name, $script:LibvirtMetadata, '--config') -Quiet
    [string] $installation = if ("$record" -match 'installed') {
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

function Add-LibvirtVolume {
    <#
    .SYNOPSIS
    A file uploaded into the pool as a volume of its size, unless one of the
    name is there.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Pool,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if ($null -ne (Invoke-Virsh -Argument @('vol-info', '--pool', $Pool, $Name) -Quiet)) {
        return
    }
    [long] $size = (Get-Item -LiteralPath $Path).Length
    Invoke-Virsh -Argument @('vol-create-as', $Pool, $Name, "$size", '--format', 'raw') | Out-Null
    Invoke-Virsh -Argument @('vol-upload', '--pool', $Pool, $Name, $Path) | Out-Null
}

function Start-LibvirtMachineInstallation {
    <#
    .SYNOPSIS
    Checks the ISO against its SHA-256, puts it, a new disk and the answer
    medium in the pool, defines the domain and starts it.
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
    [string] $pool = $Instance['pool']
    [hashtable] $volume = Get-LibvirtVolumeName -Instance $Instance
    Add-LibvirtVolume -Pool $pool -Name $volume.Image -Path $iso
    if ($null -eq (Invoke-Virsh -Argument @('vol-info', '--pool', $pool, $volume.Disk) -Quiet)) {
        Invoke-Virsh -Argument @('vol-create-as', $pool, $volume.Disk,
            "$($Instance['diskGB'])G", '--format', 'qcow2') | Out-Null
    }
    [hashtable] $asked = @{
        Machine = [pscustomobject] $Instance
        MacAddress = Get-MachineMacAddress -Address $Instance['address'] -Prefix (
            $script:LibvirtMacPrefix)
        GuestPackage = 'qemu-guest-agent'
    }
    [string] $answer = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath $volume.Answer
    try {
        [hashtable] $medium = Get-MachineAnswerMedium @asked
        New-MachineAnswerMedium -Path $answer -Medium $medium -Confirm:$false
        Add-LibvirtVolume -Pool $pool -Name $volume.Answer -Path $answer
    }
    finally {
        Remove-Item -LiteralPath $answer -Force -ErrorAction Ignore
    }
    Invoke-VirshDefinition -Command 'define' -Definition (
        Get-LibvirtMachineDefinition -Instance $Instance)
    Start-LibvirtMachine -Instance $Instance
}

function Start-LibvirtMachine {
    <#
    .SYNOPSIS
    Starts the domain. A Windows ISO boots only after "Press any key to boot
    from CD or DVD", so for its first twenty seconds Space is pressed; once
    Windows is on the disk the disk boots and the prompt is never shown.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    Invoke-Virsh -Argument @('start', $name) | Out-Null
    if (-not (Test-LibvirtWindows -Instance $Instance)) {
        return
    }
    [datetime] $until = [datetime]::UtcNow.AddSeconds(20)
    while ([datetime]::UtcNow -lt $until) {
        Invoke-Virsh -Argument @('send-key', $name, 'KEY_SPACE') -Quiet | Out-Null
        Start-Sleep -Milliseconds 500
    }
}

function Complete-LibvirtMachineInstallation {
    <#
    .SYNOPSIS
    Empties both DVD drives, deletes the answer medium, which holds the
    encoded Administrator password or the key, and records the machine
    installed in its domain's metadata.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    foreach ($target in $script:LibvirtInstallTarget, $script:LibvirtAnswerTarget) {
        [string[]] $eject = @('change-media', $name, $target, '--eject', '--config', '--live')
        Invoke-Virsh -Argument $eject -Quiet | Out-Null
    }
    [hashtable] $volume = Get-LibvirtVolumeName -Instance $Instance
    Invoke-Virsh -Argument @('vol-delete', '--pool', $Instance['pool'], $volume.Answer) -Quiet |
        Out-Null
    Invoke-Virsh -Argument @('metadata', $name, $script:LibvirtMetadata, '--key', 'xmip',
        '--set', "<machine installed='yes'/>", '--config') | Out-Null
}

function Set-LibvirtMachine {
    <#
    .SYNOPSIS
    Moves the machine on: one never defined is started installing, an
    installed one that is off is started from its disk, one whose guest
    answers has its media removed. One still installing is left to it.
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
        'Installing' {
            Write-Warning -Message (
                "$($Instance['name']): installing from its ISO; run set again once it has.")
        }
    }
}
