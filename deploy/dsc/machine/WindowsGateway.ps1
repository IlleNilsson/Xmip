# The way out a Windows machine of an environment gives the machines whose
# internet says so: NAT for the network's prefix, Routing and Remote
# Access's, out of its second adapter, the uplink, onto the owner's network
# behind his firewall, the uplink kept out of the domain where the machine
# is its controller (the owner, 2026-11-24: "A good choice would be the DC",
# "The DC would be behind my firewall"). Each rule, and Microsoft's
# documentation for it: deploy/dsc/README.md, "The way out". One home for
# both technologies (ADR-0015, amendment 2026-11-24): Microsoft DSC's
# Xmip.Environment/Gateway sends it whole into the machine's session
# (EnvironmentGateway.ps1), and Ansible's xmip_gateway role hands it whole
# to win_powershell, so it runs under Windows PowerShell and needs no
# PowerShell 7.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-WindowsGatewayAdapter {
    <#
    .SYNOPSIS
    The machine's two adapters: Inner, the one holding the network's address,
    and Uplink, its one other physical adapter, each $null where it is not
    there; Others, how many adapters beside Inner it has; Rule, the name of
    the inbound rule that blocks the uplink; and Sides, the NAT's two, the
    uplink translated in full and the network's adapter private, each with
    Held and Line, the lines of netsh's dump that hold it, in any mode and
    in its own.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Address
    )

    [hashtable] $adapter = @{
        Inner = $null; Uplink = $null; Others = 0; Rule = 'Xmip-Uplink-Inbound'; Sides = @() }
    [object[]] $held = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $Address })
    if ($held.Count -eq 0) {
        return $adapter
    }
    $adapter.Inner = Get-NetAdapter -InterfaceIndex $held[0].InterfaceIndex
    [object[]] $others = @(Get-NetAdapter -Physical | Where-Object {
        $_.InterfaceIndex -ne $adapter.Inner.InterfaceIndex })
    $adapter.Others = $others.Count
    if ($others.Count -eq 1) {
        $adapter.Uplink = $others[0]
        $adapter.Sides = @(@{ Name = $others[0].Name; Mode = 'FULL' }
            @{ Name = $adapter.Inner.Name; Mode = 'PRIVATE' })
        foreach ($side in $adapter.Sides) {
            $side.Held = '(?im)^\s*add interface name\s*=\s*"?' + [regex]::Escape($side.Name) +
            '"?\s+mode\s*='
            $side.Line = $side.Held + '\s*' + $side.Mode + '\s*$'
        }
    }
    return $adapter
}

function Test-WindowsGatewayPrefix {
    <#
    .SYNOPSIS
    Whether an address is an IPv4 address inside the prefix, CIDR notation.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Address,

        [Parameter(Mandatory = $true)]
        [string] $Prefix
    )

    [ipaddress] $ip = [ipaddress]::Parse($Address)
    if ("$($ip.AddressFamily)" -ne 'InterNetwork') {
        return $false
    }
    [string[]] $part = $Prefix -split '/'
    [byte[]] $held = $ip.GetAddressBytes()
    [byte[]] $network = ([ipaddress]::Parse($part[0])).GetAddressBytes()
    [int] $bits = [int] $part[1]
    for ([int] $octet = 0; $octet -lt 4; $octet++) {
        [int] $taken = [Math]::Min(8, [Math]::Max(0, $bits - 8 * $octet))
        [int] $mask = (0xFF -shl (8 - $taken)) -band 0xFF
        if (($held[$octet] -band $mask) -ne ($network[$octet] -band $mask)) {
            return $false
        }
    }
    return $true
}

function Get-WindowsGatewayRecord {
    <#
    .SYNOPSIS
    Every A or AAAA record of the machine's DNS server, in a primary forward
    zone, of the machine's name, of the zone's own name or of gc, that holds
    an address outside the network: an address of the uplink's, which no one
    on the network reaches.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prefix
    )

    [string[]] $named = @($env:COMPUTERNAME, '@', 'gc')
    [object[]] $zones = @(Get-DnsServerZone | Where-Object {
        -not $_.IsReverseLookupZone -and -not $_.IsAutoCreated -and "$($_.ZoneType)" -eq 'Primary'
    })
    foreach ($zone in $zones) {
        foreach ($record in @(Get-DnsServerResourceRecord -ZoneName $zone.ZoneName | Where-Object {
            "$($_.RecordType)" -in @('A', 'AAAA') -and $_.HostName -in $named })) {
            [string] $held = if ("$($record.RecordType)" -eq 'A') {
                "$($record.RecordData.IPv4Address)"
            }
            else { "$($record.RecordData.IPv6Address)" }
            if (-not (Test-WindowsGatewayPrefix -Address $held -Prefix $Prefix)) {
                [pscustomobject] @{ ZoneName = $zone.ZoneName; HostName = $record.HostName
                    Address = $held; Record = $record }
            }
        }
    }
}

function Get-WindowsGatewayDns {
    <#
    .SYNOPSIS
    The machine's DNS as the gateway decides it: Serves, whether it runs the
    DNS Server service; Listening, the addresses it listens on, joined; and
    Asking, each adapter whose DNS servers the gateway decides, with those
    it asks and those it should: where the machine serves, both adapters
    its own address alone; otherwise the uplink what the other asks.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Adapter,

        [Parameter(Mandatory = $true)]
        [string] $Address
    )

    [hashtable] $dns = @{ Listening = ''
        Serves = $null -ne (Get-Service -Name DNS -ErrorAction SilentlyContinue) }
    [hashtable] $asked = @{}
    foreach ($each in @($Adapter.Inner, $Adapter.Uplink)) {
        $asked[$each.Name] = @((Get-DnsClientServerAddress -InterfaceIndex (
                    $each.InterfaceIndex) -AddressFamily IPv4).ServerAddresses) -join ','
    }
    [string] $wanted = $asked[$Adapter.Inner.Name]
    [object[]] $decided = @($Adapter.Uplink | Where-Object { $wanted })
    if ($dns.Serves) {
        $dns.Listening = @((Get-DnsServerSetting -All).ListeningIPAddress | Where-Object { $_ } |
            ForEach-Object { "$_" }) -join ','
        $wanted = $Address
        $decided = @($Adapter.Inner, $Adapter.Uplink)
    }
    $dns.Asking = @($decided | ForEach-Object {
            @{ Adapter = $_; Asked = $asked[$_.Name]; Wanted = $wanted } })
    return $dns
}

function Test-WindowsGatewayRule {
    <#
    .SYNOPSIS
    Whether the inbound rule that blocks everything arriving on the uplink is
    there, on, for every profile and on the uplink's interface alone.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Adapter
    )

    [object] $rule = Get-NetFirewallRule -Name $Adapter.Rule -ErrorAction SilentlyContinue
    if ($null -eq $rule) {
        return $false
    }
    [string] $on = @(Get-NetFirewallInterfaceFilter -AssociatedNetFirewallRule $rule |
        ForEach-Object { $_.InterfaceAlias }) -join ','
    return "$($rule.Enabled)" -eq 'True' -and "$($rule.Direction)" -eq 'Inbound' -and
    "$($rule.Action)" -eq 'Block' -and "$($rule.Profile)" -eq 'Any' -and
    $on -eq $Adapter.Uplink.Name
}

function Get-WindowsGatewayNatFinding {
    <#
    .SYNOPSIS
    How the machine's NAT differs from the gateway's, in words: Routing and
    Remote Access's Routing not installed, not running with the machine, or
    its NAT not holding each side in its mode.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Adapter
    )

    if ($null -eq (Get-Command -Name Get-WindowsFeature -ErrorAction SilentlyContinue)) {
        return 'Routing and Remote Access is not there: the machine is not Windows Server.'
    }
    if (-not (Get-WindowsFeature -Name Routing).Installed) {
        return 'Routing, of Routing and Remote Access, is not installed.'
    }
    [object] $service = Get-Service -Name RemoteAccess
    if ("$($service.Status)" -ne 'Running' -or "$($service.StartType)" -ne 'Automatic') {
        return 'Routing and Remote Access is not running, started with the machine.'
    }
    [string] $dump = @(& netsh routing ip nat dump) -join "`n"
    foreach ($side in @($Adapter.Sides | Where-Object { $dump -notmatch $_.Line })) {
        "The NAT does not hold $($side.Name) in mode $($side.Mode)."
    }
}

function Get-WindowsGatewayFinding {
    <#
    .SYNOPSIS
    How the machine differs from the network's gateway, in words; nothing
    when it does not.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Address,

        [Parameter(Mandatory = $true)]
        [string] $Prefix
    )

    [hashtable] $adapter = Get-WindowsGatewayAdapter -Address $Address
    if ($null -eq $adapter.Inner) {
        return "No adapter holds $Address."
    }
    if ($null -eq $adapter.Uplink) {
        return "$($adapter.Others) adapters beside the one holding $Address, not one, the uplink."
    }
    [int] $index = $adapter.Uplink.InterfaceIndex
    [string] $name = $adapter.Uplink.Name
    if ((Get-DnsClient -InterfaceIndex $index).RegisterThisConnectionsAddress) {
        "${name}: registers its address in DNS."
    }
    [hashtable] $dns = Get-WindowsGatewayDns -Adapter $adapter -Address $Address
    foreach ($side in @($dns.Asking | Where-Object { $_.Asked -ne $_.Wanted })) {
        "$($side.Adapter.Name): asks the DNS servers '$($side.Asked)', not '$($side.Wanted)'."
    }
    [string] $filter = "InterfaceIndex = $index"
    if ((Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter $filter
        ).TcpipNetbiosOptions -ne 2) {
        "${name}: NetBIOS over TCP/IP is not off."
    }
    [object] $connection = Get-NetConnectionProfile -InterfaceIndex $index -ErrorAction (
        'SilentlyContinue')
    if ($null -ne $connection -and "$($connection.NetworkCategory)" -ne 'Public') {
        "${name}: a $($connection.NetworkCategory) network, not Public."
    }
    if (-not (Test-WindowsGatewayRule -Adapter $adapter)) {
        "${name}: the inbound rule $($adapter.Rule) does not block everything arriving on it."
    }
    if ($dns.Serves) {
        if ($dns.Listening -ne $Address) {
            "The DNS server listens on '$($dns.Listening)', not $Address alone."
        }
        foreach ($record in @(Get-WindowsGatewayRecord -Prefix $Prefix)) {
            "The DNS record $($record.HostName) of $($record.ZoneName) holds $($record.Address)."
        }
    }
    Get-WindowsGatewayNatFinding -Adapter $adapter
}

function Set-WindowsGatewayDns {
    <#
    .SYNOPSIS
    Each adapter asks the DNS servers Get-WindowsGatewayDns decides; and
    where the machine runs the DNS Server service, it listens on the
    network's address alone, restarted where that changed, and every record
    of Get-WindowsGatewayRecord is removed.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Adapter,

        [Parameter(Mandatory = $true)]
        [string] $Address,

        [Parameter(Mandatory = $true)]
        [string] $Prefix
    )

    [hashtable] $dns = Get-WindowsGatewayDns -Adapter $Adapter -Address $Address
    foreach ($side in @($dns.Asking | Where-Object { $_.Asked -ne $_.Wanted })) {
        Set-DnsClientServerAddress -InterfaceIndex $side.Adapter.InterfaceIndex -ServerAddresses (
            $side.Wanted -split ',')
    }
    if (-not $dns.Serves) {
        return
    }
    if ($dns.Listening -ne $Address) {
        [object] $setting = Get-DnsServerSetting -All
        $setting.ListeningIPAddress = @($Address)
        Set-DnsServerSetting -InputObject $setting
        Restart-Service -Name DNS
    }
    foreach ($record in @(Get-WindowsGatewayRecord -Prefix $Prefix)) {
        Remove-DnsServerResourceRecord -ZoneName $record.ZoneName -InputObject $record.Record -Force
    }
}

function Set-WindowsGatewayNat {
    <#
    .SYNOPSIS
    Routing and Remote Access's Routing installed, configured as a router
    once and running with the machine, and its NAT holding the uplink in
    full and the network's adapter private.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Adapter
    )

    if (-not (Get-WindowsFeature -Name Routing).Installed) {
        Install-WindowsFeature -Name Routing -IncludeManagementTools | Out-Null
    }
    # The service is disabled until Routing and Remote Access is configured.
    if ("$((Get-Service -Name RemoteAccess).StartType)" -ne 'Automatic') {
        Install-RemoteAccess -VpnType RoutingOnly -Confirm:$false | Out-Null
    }
    if ("$((Get-Service -Name RemoteAccess).Status)" -ne 'Running') {
        Start-Service -Name RemoteAccess
    }
    [string] $dump = @(& netsh routing ip nat dump) -join "`n"
    if ($dump -notmatch '(?im)^\s*add interface') {
        & netsh routing ip nat install | Out-Null
    }
    foreach ($side in @($Adapter.Sides | Where-Object { $dump -notmatch $_.Line })) {
        [string] $act = if ($dump -match $side.Held) { 'set' } else { 'add' }
        [string[]] $said = @(& netsh routing ip nat $act interface "name=$($side.Name)" (
                "mode=$($side.Mode.ToLowerInvariant())"))
        if ($LASTEXITCODE -ne 0) {
            throw "netsh routing ip nat $act interface $($side.Name): $($said -join ' ')"
        }
    }
}

function Set-WindowsGateway {
    <#
    .SYNOPSIS
    Makes the machine the network's gateway, as Get-WindowsGatewayFinding
    reads it; a machine without its two adapters is refused, since an
    adapter is the hypervisor's to give.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Address,

        [Parameter(Mandatory = $true)]
        [string] $Prefix
    )

    [hashtable] $adapter = Get-WindowsGatewayAdapter -Address $Address
    if ($null -eq $adapter.Inner -or $null -eq $adapter.Uplink) {
        throw "REFUSED: $(Get-WindowsGatewayFinding -Address $Address -Prefix $Prefix)"
    }
    if (-not $PSCmdlet.ShouldProcess($adapter.Uplink.Name, 'Make the network''s way out')) {
        return
    }
    [int] $index = $adapter.Uplink.InterfaceIndex
    Set-DnsClient -InterfaceIndex $index -RegisterThisConnectionsAddress $false
    [object] $configuration = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter (
        "InterfaceIndex = $index")
    [hashtable] $off = @{ TcpipNetbiosOptions = [uint32] 2 }
    Invoke-CimMethod -InputObject $configuration -MethodName SetTcpipNetbios -Arguments $off |
        Out-Null
    if ($null -ne (Get-NetConnectionProfile -InterfaceIndex $index -ErrorAction SilentlyContinue)) {
        Set-NetConnectionProfile -InterfaceIndex $index -NetworkCategory Public
    }
    if (-not (Test-WindowsGatewayRule -Adapter $adapter)) {
        [object] $old = Get-NetFirewallRule -Name $adapter.Rule -ErrorAction SilentlyContinue
        if ($null -ne $old) {
            $old | Remove-NetFirewallRule
        }
        [hashtable] $rule = @{
            Name = $adapter.Rule; DisplayName = 'Xmip: nothing in through the uplink'
            Direction = 'Inbound'; Action = 'Block'; Profile = 'Any'
            InterfaceAlias = $adapter.Uplink.Name; Enabled = 'True'
        }
        New-NetFirewallRule @rule | Out-Null
    }
    Set-WindowsGatewayDns -Adapter $adapter -Address $Address -Prefix $Prefix
    Set-WindowsGatewayNat -Adapter $adapter
}
