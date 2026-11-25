#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipDeployFreeNetwork {
    <#
        .SYNOPSIS
            A private /24 no prefix in -Taken overlaps: the first of
            10.77.0.0/24 to 10.77.255.0/24. Refused in words where all are
            taken.

        .DESCRIPTION
            Where a cluster file's [environment] names no network, Xmip picks
            one on the host (the coordinator, 2026-11-25), and the private
            state keeps it, so a later run, the host then on it, keeps it too.

        .PARAMETER Taken
            The host's prefixes, address/length, as Get-XmipDeployHostPrefix
            answers them.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Taken
    )

    [object[]] $ranges = @($Taken | ForEach-Object { ConvertTo-XmipDeployRange -Prefix $_ })
    foreach ($third in 0..255) {
        [string] $candidate = "10.77.$third.0/24"
        $range = ConvertTo-XmipDeployRange -Prefix $candidate
        [bool] $overlaps = @($ranges | Where-Object {
                $_.First -le $range.Last -and $range.First -le $_.Last }).Count -gt 0
        if (-not $overlaps) {
            return $candidate
        }
    }
    throw ('REFUSED: every network of 10.77.0.0/16 overlaps one of this host''s: name one ' +
        'in the cluster file''s [environment] network.')
}

function ConvertTo-XmipDeployRange {
    <#
        .SYNOPSIS
            An IPv4 prefix, address/length, as its first and last addresses,
            each a number: what Get-XmipDeployFreeNetwork compares and
            Get-XmipDeployEnvironment counts addresses in.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Prefix
    )

    if ($Prefix -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$' -or [int] $Matches[2] -gt 32) {
        throw "REFUSED: $Prefix is no IPv4 network, address/length: 10.77.0.0/24."
    }
    [int] $length = [int] $Matches[2]
    [byte[]] $bytes = [Net.IPAddress]::Parse($Matches[1]).GetAddressBytes()
    [Array]::Reverse($bytes)
    [uint64] $address = [BitConverter]::ToUInt32($bytes, 0)
    [uint64] $size = [uint64] 1 -shl (32 - $length)
    [uint64] $first = $address - ($address % $size)
    return [pscustomobject] @{ First = $first; Last = $first + $size - 1; Length = $length }
}

function ConvertFrom-XmipDeployNumber {
    <#
        .SYNOPSIS
            An IPv4 address from its number, as ConvertTo-XmipDeployRange
            counts them.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [uint64] $Number
    )

    [byte[]] $bytes = [BitConverter]::GetBytes([uint32] $Number)
    [Array]::Reverse($bytes)
    return [Net.IPAddress]::new($bytes).ToString()
}

function Get-XmipDeployHostPrefix {
    <#
        .SYNOPSIS
            Every IPv4 prefix this host has an address on, address/length:
            Windows' own Get-NetIPAddress, or iproute2's ip on Linux.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($IsWindows) {
        return @(Get-NetIPAddress -AddressFamily IPv4 | ForEach-Object {
                "$($_.IPAddress)/$($_.PrefixLength)" })
    }
    [string] $said = (& ip -j -4 address show) -join "`n"
    foreach ($link in @($said | ConvertFrom-Json)) {
        foreach ($address in @($link.addr_info)) {
            "$($address.local)/$($address.prefixlen)"
        }
    }
}

function Get-XmipDeployUplink {
    <#
        .SYNOPSIS
            The switch (Hyper-V: an external one) or bridge (libvirt) the
            gateway machine's second adapter is on: the one given, else the
            host's one. Refused in words where the host has none or several,
            naming them: the uplink takes a host adapter, so it is the
            owner's to make, once, and Xmip never makes, changes or removes
            it (ADR-0015, amendment 2026-11-24).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Given = '',

        [Parameter(Mandatory)]
        [string] $Hypervisor
    )

    if ($Given) {
        return $Given
    }
    [string[]] $there = @(Get-XmipDeployHostSwitch -Hypervisor $Hypervisor)
    if ($there.Count -eq 1) {
        return $there[0]
    }
    [string] $kind = if ($Hypervisor -eq 'hyperv') { 'external switch' } else { 'bridge' }
    [string] $found = if ($there.Count -eq 0) { 'it has none' }
    else { "it has $($there -join ', '): name one with -Uplink" }
    throw ("REFUSED: the gateway reaches past the network through an uplink, the host's one " +
        "$kind onto its own network, behind your firewall; $found (deploy/dsc/README.md, " +
        'Before the first run).')
}

function Get-XmipDeployHostSwitch {
    <#
        .SYNOPSIS
            The host's uplinks: Hyper-V's external switches, or the Linux
            host's bridges that are no libvirt network's (virbr*).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Hypervisor
    )

    if ($Hypervisor -eq 'hyperv' -and -not $IsWindows) {
        return @()
    }
    if ($Hypervisor -eq 'hyperv') {
        return @(Get-VMSwitch -SwitchType External | ForEach-Object { $_.Name })
    }
    [string] $said = (& ip -j link show type bridge) -join "`n"
    return @(@($said | ConvertFrom-Json) | ForEach-Object { $_.ifname } |
            Where-Object { $_ -notlike 'virbr*' })
}

function Get-XmipDeployDiskRoot {
    <#
        .SYNOPSIS
            Where this host keeps virtual machines' disks: Hyper-V's own
            folder of virtual hard disks, or libvirt's /var/lib/libvirt/images.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Hypervisor
    )

    if ($Hypervisor -eq 'hyperv' -and -not $IsWindows) {
        throw ('REFUSED: from WSL the Windows host''s folder for disks is not asked: name it ' +
            'with -DiskFolder.')
    }
    if ($Hypervisor -eq 'hyperv') {
        return (Get-VMHost).VirtualHardDiskPath
    }
    return '/var/lib/libvirt/images'
}
