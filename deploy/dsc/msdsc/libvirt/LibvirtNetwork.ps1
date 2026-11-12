#requires -PSEdition Core
#requires -Version 7.7.0
# The Xmip.Libvirt/Network and Xmip.Libvirt/Pool kinds (libvirt.resource.ps1).
#
# Network: a libvirt network with NAT, the host its gateway, whose DHCP gives
# each machine its address by its static MAC and whose DNS answers each
# machine's name and every name the environment adds (the cluster's and its
# nodes'), so no DNS server of the environment's own is needed.
#
# Pool: a directory pool libvirt keeps, where each machine's disk, its answer
# medium and the installation images are volumes any machine can read.
#
# What each is, is deploy/dsc/machine's (LibvirtDefinition.ps1).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LibvirtNetworkFinding {
    <#
    .SYNOPSIS
    How the network differs from its instance, in words; nothing when not.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [string] $found = Invoke-Virsh -Argument @('net-dumpxml', '--inactive', $name) -Quiet
    if ([string]::IsNullOrEmpty($found)) {
        Write-Output -InputObject "${name}: no such network."
        return
    }
    [string] $have = Get-LibvirtNetworkSummary -Xml ([xml] $found)
    [string] $want = Get-LibvirtNetworkSummary -Xml ([xml] (
        Get-LibvirtNetworkDefinition -Instance $Instance))
    if ($have -ne $want) {
        Write-Output -InputObject "${name}: its definition is not the environment's."
    }
    [string] $info = Invoke-Virsh -Argument @('net-info', $name)
    if ($info -notmatch '(?m)^Active:\s+yes') {
        Write-Output -InputObject "${name}: not started."
    }
    if ($info -notmatch '(?m)^Autostart:\s+yes') {
        Write-Output -InputObject "${name}: not started with the host."
    }
}

function Get-LibvirtNetworkSummary {
    <#
    .SYNOPSIS
    What of a network definition the environment decides, as one comparable
    string: the forward mode, the bridge, the gateway and prefix, the DHCP
    hosts and the DNS hosts, sorted. What libvirt adds itself (a UUID, the
    bridge's MAC, defaults) is left out.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [xml] $Xml
    )

    [Xml.XmlElement] $network = $Xml.DocumentElement
    [string[]] $line = @(
        "forward $($network.SelectSingleNode('forward/@mode').Value)"
        "bridge $($network.SelectSingleNode('bridge/@name').Value)"
        "ip $($network.SelectSingleNode('ip/@address').Value)/" +
            "$($network.SelectSingleNode('ip/@prefix').Value)"
    )
    [string[]] $hosts = @(
        foreach ($entry in @($network.SelectNodes('ip/dhcp/host'))) {
            "dhcp $($entry.GetAttribute('mac').ToLowerInvariant()) " +
                "$($entry.GetAttribute('ip')) $($entry.GetAttribute('name'))"
        }
        foreach ($entry in @($network.SelectNodes('dns/host'))) {
            foreach ($hostName in @($entry.SelectNodes('hostname'))) {
                "dns $($entry.GetAttribute('ip')) $($hostName.InnerText)"
            }
        }
    )
    return (@($line) + @($hosts | Sort-Object)) -join "`n"
}

function Set-LibvirtNetwork {
    <#
    .SYNOPSIS
    Defines the network as its instance says, starts it and starts it with
    the host. A network whose definition changed is defined anew and, if it
    ran, restarted: its machines lose their link for that moment.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [string[]] $finding = @(Get-LibvirtNetworkFinding -Instance $Instance)
    if ($finding.Count -eq 0 -or -not $PSCmdlet.ShouldProcess($name, 'Define and start')) {
        return
    }
    if ($finding -match 'definition|no such') {
        Invoke-VirshDefinition -Command 'net-define' -Definition (
            Get-LibvirtNetworkDefinition -Instance $Instance)
        if ($null -ne (Invoke-Virsh -Argument @('net-info', $name) -Quiet) -and
            (Invoke-Virsh -Argument @('net-info', $name)) -match '(?m)^Active:\s+yes') {
            Invoke-Virsh -Argument @('net-destroy', $name) | Out-Null
        }
    }
    if ((Invoke-Virsh -Argument @('net-info', $name)) -notmatch '(?m)^Active:\s+yes') {
        Invoke-Virsh -Argument @('net-start', $name) | Out-Null
    }
    Invoke-Virsh -Argument @('net-autostart', $name) | Out-Null
}

function Get-LibvirtPoolFinding {
    <#
    .SYNOPSIS
    How the pool differs from its instance (name, path), in words.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [string] $found = Invoke-Virsh -Argument @('pool-dumpxml', '--inactive', $name) -Quiet
    if ([string]::IsNullOrEmpty($found)) {
        Write-Output -InputObject "${name}: no such pool."
        return
    }
    [xml] $pool = $found
    if ($pool.pool.type -ne 'dir' -or $pool.pool.target.path -ne $Instance['path']) {
        Write-Output -InputObject "${name}: not a directory pool at $($Instance['path'])."
    }
    [string] $info = Invoke-Virsh -Argument @('pool-info', $name)
    if ($info -notmatch '(?m)^State:\s+running') {
        Write-Output -InputObject "${name}: not started."
    }
    if ($info -notmatch '(?m)^Autostart:\s+yes') {
        Write-Output -InputObject "${name}: not started with the host."
    }
}

function Set-LibvirtPool {
    <#
    .SYNOPSIS
    Defines the directory pool, makes its directory, starts it and starts it
    with the host. A pool at another path is refused, never moved: its
    volumes are machines' disks.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [string[]] $finding = @(Get-LibvirtPoolFinding -Instance $Instance)
    if ($finding.Count -eq 0 -or -not $PSCmdlet.ShouldProcess($name, 'Define and start')) {
        return
    }
    if ($finding -match 'not a directory pool') {
        throw "REFUSED: $($finding -match 'not a directory pool'); it is not moved."
    }
    if ($finding -match 'no such pool') {
        Invoke-VirshDefinition -Command 'pool-define' -Definition (
            Get-LibvirtPoolDefinition -Instance $Instance)
        Invoke-Virsh -Argument @('pool-build', $name) | Out-Null
    }
    if ((Invoke-Virsh -Argument @('pool-info', $name)) -notmatch '(?m)^State:\s+running') {
        Invoke-Virsh -Argument @('pool-start', $name) | Out-Null
    }
    Invoke-Virsh -Argument @('pool-autostart', $name) | Out-Null
}
