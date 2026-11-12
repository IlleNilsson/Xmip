#requires -PSEdition Core
#requires -Version 7.7.0
# What installing one machine on a libvirt host does, for both technologies:
# virsh on the system connection; the machine's media put in the pool whole,
# its domain defined and started, Space pressed for a Windows ISO; and its
# installation completed, its media taken out, its answer medium deleted and
# its domain's record written, naming the technology that made it. Microsoft
# DSC's Xmip.Libvirt resources dot-source it and Ansible's xmip_machine role
# asks machine.ps1, so neither does any of it its own way. Every rule about a
# network, a pool or a domain is libvirt's.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'LibvirtDefinition.ps1')

# The system connection: the one libvirt's virtqemud serves as root, whose
# networks get a bridge and NAT and whose pools any machine reads.
$script:LibvirtConnection = 'qemu:///system'

function Invoke-Virsh {
    <#
    .SYNOPSIS
    Runs virsh on the system connection and answers its output; a failure is
    refused with virsh's own words. -Quiet answers $null instead of refusing,
    for a question whose "no" is a failure, such as an unknown name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Argument,

        [Parameter()]
        [switch] $Quiet
    )

    [string[]] $output = @(& virsh --connect $script:LibvirtConnection @Argument 2>&1 |
        ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) {
        if ($Quiet) {
            return $null
        }
        throw "REFUSED: virsh $($Argument -join ' '): $($output -join ' ')"
    }
    return ($output -join "`n")
}

function Invoke-VirshDefinition {
    <#
    .SYNOPSIS
    Hands virsh a definition (net-define, define) as the file it reads.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command,

        [Parameter(Mandatory = $true)]
        [string] $Definition
    )

    [string] $file = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($file, $Definition, [Text.UTF8Encoding]::new($false))
        Invoke-Virsh -Argument @($Command, $file) | Out-Null
    }
    finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction Ignore
    }
}

function Test-LibvirtVolumeWhole {
    <#
    .SYNOPSIS
    Whether the pool holds a volume of the name, all of it written. A volume
    is made sparse and then uploaded, so one an upload that stopped left
    behind is allocated short of its capacity, and is never trusted by its
    name: answers $null where there is none, $false where it is short.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Pool,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    [string] $info = Invoke-Virsh -Argument @('vol-info', '--bytes', '--pool', $Pool, $Name) -Quiet
    if ([string]::IsNullOrEmpty($info)) {
        return $null
    }
    [long] $capacity = [regex]::Match($info, '(?m)^Capacity:\s+(\d+)').Groups[1].Value
    [long] $allocation = [regex]::Match($info, '(?m)^Allocation:\s+(\d+)').Groups[1].Value
    return $allocation -ge $capacity
}

function Add-LibvirtVolume {
    <#
    .SYNOPSIS
    A file put in the pool as a volume of its size, unless the pool holds
    one of the name whole: made sparse, then uploaded. One an upload that
    stopped left short is deleted first, so a volume named by an ISO's
    SHA-256 holds the whole ISO, or is not there.
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

    [object] $whole = Test-LibvirtVolumeWhole -Pool $Pool -Name $Name
    if ($true -eq $whole) {
        return
    }
    if ($false -eq $whole) {
        Invoke-Virsh -Argument @('vol-delete', '--pool', $Pool, $Name) | Out-Null
    }
    [long] $size = (Get-Item -LiteralPath $Path).Length
    Invoke-Virsh -Argument @('vol-create-as', $Pool, $Name, "$size", '--allocation', '0',
        '--format', 'raw') | Out-Null
    Invoke-Virsh -Argument @('vol-upload', '--pool', $Pool, $Name, $Path) | Out-Null
}

function Get-LibvirtMachineRecord {
    <#
    .SYNOPSIS
    The machine as its host knows it: whether its domain is defined, and
    whether its record says it is installed. A record another technology
    wrote is refused: an environment is made by one, never a mix.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [bool] $defined = $null -ne (Invoke-Virsh -Argument @('domstate', $name) -Quiet)
    [string] $record = if ($defined) {
        Invoke-Virsh -Argument @('metadata', $name, $script:LibvirtMetadata, '--config') -Quiet
    }
    if ([string]::IsNullOrWhiteSpace($record)) {
        return @{ defined = $defined; installed = $false }
    }
    [Xml.XmlElement] $machine = ([xml] $record).DocumentElement
    [string] $made = $machine.GetAttribute('technology')
    if ($made -ne [string] $Instance['technology']) {
        throw ("REFUSED: $name was made by '$made', not $($Instance['technology']): an " +
            'environment is made by one technology, never a mix. Remove it first ' +
            '(deploy/dsc/README.md, Starting again from nothing).')
    }
    return @{ defined = $defined; installed = $machine.GetAttribute('installed') -eq 'yes' }
}

function New-LibvirtPrivateFolder {
    <#
    .SYNOPSIS
    A folder made new for one answer medium, readable by this account alone:
    named at random under the temporary folder and, on Linux and macOS,
    0700, as .NET makes it, so no other account reads it or makes it first.
    #>
    [CmdletBinding()]
    [OutputType([IO.DirectoryInfo])]
    param()

    return [IO.Directory]::CreateTempSubdirectory('xmip-answer-')
}

function Start-LibvirtMachineInstallation {
    <#
    .SYNOPSIS
    Puts the ISO in the pool, checked against its SHA-256, a new disk and
    the answer medium, each whole; defines the domain and starts it. The
    ISO's volume is named by its SHA-256 and made only once it was checked,
    so a machine of an image already in the pool reads the ISO no more: a
    DVD's gigabytes are hashed once, not once per machine. The answer medium
    holds the machine's keys or password, so it is written in a folder made
    for it alone, 0700 and named at random, and that folder is removed.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $iso = $Instance['image'].path
    [string] $pool = $Instance['pool']
    [hashtable] $plan = Get-LibvirtMachinePlan -Instance $Instance
    [string] $image = $plan.volume.Image
    if ($true -ne (Test-LibvirtVolumeWhole -Pool $pool -Name $image)) {
        [string] $hash = (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash
        if ($hash -ne $Instance['image'].sha256) {
            throw "REFUSED: $iso has SHA-256 $hash, not $($Instance['image'].sha256)."
        }
        Add-LibvirtVolume -Pool $pool -Name $image -Path $iso
    }
    [string] $disk = $plan.volume.Disk
    if ($null -eq (Invoke-Virsh -Argument @('vol-info', '--pool', $pool, $disk) -Quiet)) {
        Invoke-Virsh -Argument @('vol-create-as', $pool, $plan.volume.Disk,
            "$($Instance['diskGB'])G", '--format', 'qcow2') | Out-Null
    }
    if ($true -ne (Test-LibvirtVolumeWhole -Pool $pool -Name $plan.volume.Answer)) {
        [IO.DirectoryInfo] $private = New-LibvirtPrivateFolder
        try {
            [string] $answer = Join-Path -Path $private.FullName -ChildPath $plan.volume.Answer
            New-LibvirtAnswerMedium -Instance $Instance -Path $answer -Confirm:$false
            Add-LibvirtVolume -Pool $pool -Name $plan.volume.Answer -Path $answer
        }
        finally {
            Remove-Item -LiteralPath $private.FullName -Recurse -Force -ErrorAction Ignore
        }
    }
    Invoke-VirshDefinition -Command 'define' -Definition $plan.definition
    Start-LibvirtMachine -Instance $Instance
}

function Start-LibvirtMachine {
    <#
    .SYNOPSIS
    Starts the domain where it is not running. A Windows ISO boots only
    after "Press any key to boot from CD or DVD", so for its first twenty
    seconds Space is pressed; once Windows is on the disk the disk boots and
    the prompt is never shown.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    if ((Invoke-Virsh -Argument @('domstate', $name)) -match '^running') {
        return
    }
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
    Empties both DVD drives and deletes the answer medium, which holds the
    encoded Administrator password or the keys, then records the machine
    installed in its domain's metadata, naming the technology that made it.
    A drive still holding a medium, or an answer medium still in the pool,
    is refused before the record is written, so the next run tries again.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [hashtable] $plan = Get-LibvirtMachinePlan -Instance $Instance
    [string[]] $where = @('--config')
    if ((Invoke-Virsh -Argument @('domstate', $name)) -match '^running') {
        $where += '--live'
    }
    foreach ($target in $plan.drives) {
        # A drive already empty refuses the eject; the listing below is the answer.
        Invoke-Virsh -Argument (@('change-media', $name, $target, '--eject') + $where) -Quiet |
            Out-Null
    }
    foreach ($listing in @('--inactive'), @()) {
        [string] $drives = Invoke-Virsh -Argument (@('domblklist', $name, '--details') + $listing)
        foreach ($target in $plan.drives) {
            if ($drives -match "(?m)^\s*\S+\s+cdrom\s+$target\s+(?!-\s*$)\S") {
                throw "REFUSED: $name`: its drive $target still holds a medium."
            }
        }
    }
    [string] $pool = $Instance['pool']
    [string[]] $answer = @('--pool', $pool, $plan.volume.Answer)
    Invoke-Virsh -Argument (@('vol-delete') + $answer) -Quiet | Out-Null
    if ($null -ne (Invoke-Virsh -Argument (@('vol-info') + $answer) -Quiet)) {
        throw "REFUSED: $name`: its answer medium $($plan.volume.Answer) is still in $pool."
    }
    Invoke-Virsh -Argument @('metadata', $name, $plan.metadata.uri, '--key', $plan.metadata.key,
        '--set', $plan.metadata.record, '--config') | Out-Null
}
