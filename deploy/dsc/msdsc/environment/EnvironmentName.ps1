#requires -Version 7.6

<#
    The Name kind of environment.resource.ps1: on the environment's DNS
    server, an A record for the cluster and for each node, in the zone,
    each holding exactly the addresses it is given. A node finds another by
    its name (ADR-0053; ADR-0028, amendment 2026-10-21), and this is where
    the name comes from. Dot-sourced by environment.resource.ps1 and by
    test/MsdscEnvironment.Test.ps1.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Get-EnvironmentNameAddress {
    <#
    .SYNOPSIS
    The addresses one name's A records hold in the zone, sorted; none where
    it has none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Zone,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    [hashtable] $asked = @{
        ZoneName    = $Zone
        Name        = $Name
        RRType      = 'A'
        ErrorAction = 'SilentlyContinue'
    }

    return @(Get-DnsServerResourceRecord @asked |
            ForEach-Object { $_.RecordData.IPv4Address.IPAddressToString } | Sort-Object)
}

function Get-EnvironmentName {
    <#
    .SYNOPSIS
    The zone's state: _exist where it is there and every name holds
    exactly its addresses.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $state = $Instance.Clone()
    $state._exist = $null -ne (Get-DnsServerZone -Name $Instance.zone -ErrorAction SilentlyContinue)

    foreach ($record in @($Instance.records)) {
        [string] $have = (Get-EnvironmentNameAddress -Zone $Instance.zone -Name $record.name) -join ','
        [string] $want = (@($record.addresses) | Sort-Object) -join ','
        $state._exist = $state._exist -and $have -eq $want
    }

    return $state
}

function Set-EnvironmentName {
    <#
    .SYNOPSIS
    Make the zone where it is not there, a primary zone in a file, and give
    each name exactly its addresses.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $zone = $Instance.zone

    if (-not $PSCmdlet.ShouldProcess($zone, 'Give the cluster and its nodes their names')) {
        return
    }

    if ($null -eq (Get-DnsServerZone -Name $zone -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -Name $zone -ZoneFile "$zone.dns"
    }

    foreach ($record in @($Instance.records)) {
        [string[]] $have = @(Get-EnvironmentNameAddress -Zone $zone -Name $record.name)
        [string[]] $want = @($record.addresses)

        foreach ($address in $have | Where-Object { $_ -notin $want }) {
            [hashtable] $gone = @{
                ZoneName   = $zone
                Name       = $record.name
                RRType     = 'A'
                RecordData = $address
                Force      = $true
            }
            Remove-DnsServerResourceRecord @gone
        }

        foreach ($address in $want | Where-Object { $_ -notin $have }) {
            Add-DnsServerResourceRecordA -ZoneName $zone -Name $record.name -IPv4Address $address
        }
    }
}
