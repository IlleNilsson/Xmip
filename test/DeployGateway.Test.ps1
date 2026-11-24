#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The domain controller as the network's gateway (ADR-0015, amendment
    2026-11-24; the owner, 2026-11-24: "A good choice would be the DC", and
    "The DC would be behind my firewall"), without a machine.

    - The environment file: [network] gateway_machine names a Windows machine
      of the environment and uplink the switch or bridge its second adapter
      is on. Each machine whose internet says so is given the gateway
      machine's address as its gateway; the gateway machine none on the
      network, and the uplink; every other machine no uplink. Refused: a
      name that is no Windows machine, no uplink, and the host's NAT beside
      it. Left out, the host is the gateway as before.
    - msdsc applies gateway.dsc.yaml after the domain's controller and
      before the names; Ansible's inventory names the gateway machine in
      xmip_gateway, played after the machines and before the names.
    - deploy/dsc/machine/WindowsGateway.ps1, every Windows command a stub
      over a machine held in memory: the uplink registers nothing in DNS,
      asks the machine's own DNS server, has no NetBIOS, is Public and lets
      nothing in by a rule on its interface; the DNS server listens on the
      network alone and no record of the machine's names holds an outside
      address; Routing and Remote Access's NAT holds the uplink in full and
      the network's adapter private. A fresh machine is found differing in
      each, made so, and then found as it is; a machine without its second
      adapter is refused, and one that is not Windows Server is said so.
    - Xmip.Environment/Gateway runs that one script in the machine's
      session, and answers a machine that does not answer as absent.
    - One file holds each rule both technologies run.

    The machines themselves are proved by running Deploy-XmipEnvironment:
    deploy/dsc/README.md.

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Machine = Join-Path $script:Root 'deploy/dsc/machine'
    [string] $script:Environment = Join-Path $script:Root 'deploy/dsc/msdsc/environment'
    . (Join-Path $script:Machine 'WindowsGateway.ps1')
    . (Join-Path $script:Environment 'EnvironmentGateway.ps1')

    # An example environment, its values given, changed as asked.
    function New-Environment {
        param(
            [string] $Example = 'hyperv',
            [hashtable] $Network = @{}
        )

        [string] $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $environment = Read-XmipTestEnvironment -Path (
            Join-Path $script:Root "deploy/dsc/$Example.example.toml") -Folder $folder
        foreach ($key in $Network.Keys) {
            if ($null -eq $Network[$key]) {
                $environment['network'].Remove($key)
            }
            else {
                $environment['network'][$key] = $Network[$key]
            }
        }
        return @{ Environment = $environment; Folder = $folder }
    }

    # The environment as Get-XmipDeployEnvironment reads it.
    function Read-Environment {
        param([hashtable] $Made)

        & (Get-Module -Name Xmip) {
            param($Environment, $Estate, $Run)
            Get-XmipDeployEnvironment -Environment $Environment -Estate $Estate -Run $Run
        } $Made.Environment $script:Root $Made.Folder
    }

    # A gateway machine held in memory: its network's adapter and its
    # uplink, which an outside DHCP server addressed from the documentation
    # range (RFC 5737), every setting as Windows leaves it, its DNS server's
    # zones holding the uplink's address too, and no Routing.
    function Reset-FakeGateway {
        $script:Gw = @{
            Adapters = @(
                [pscustomobject] @{ Name = 'Ethernet'; InterfaceIndex = 4 }
                [pscustomobject] @{ Name = 'Ethernet 2'; InterfaceIndex = 7 })
            Addresses = @(
                [pscustomobject] @{ IPAddress = '10.77.0.10'; InterfaceIndex = 4 }
                [pscustomobject] @{ IPAddress = '192.0.2.50'; InterfaceIndex = 7 })
            Register = @{ 4 = $true; 7 = $true }
            Servers = @{ 4 = @('127.0.0.1'); 7 = @('192.0.2.1') }
            Netbios = @{ 4 = 0; 7 = 0 }
            Category = @{ 4 = 'DomainAuthenticated'; 7 = 'Private' }
            Rule = $null
            Services = @{
                DNS = [pscustomobject] @{ Status = 'Running'; StartType = 'Automatic' }
                RemoteAccess = [pscustomobject] @{ Status = 'Stopped'; StartType = 'Disabled' }
            }
            Server = $true
            Listening = @()
            Zones = @('xmip.test', '_msdcs.xmip.test', '0.77.10.in-addr.arpa')
            Records = [Collections.Generic.List[object]]::new()
            Routing = $false
            Nat = $null
        }
        foreach ($record in @(
                @('xmip.test', 'XMIP-DC01', '10.77.0.10'), @('xmip.test', 'XMIP-DC01', '192.0.2.50')
                @('xmip.test', '@', '10.77.0.10'), @('xmip.test', '@', '192.0.2.50')
                @('xmip.test', 'RX1', '10.77.0.41'), @('_msdcs.xmip.test', 'gc', '192.0.2.50'))) {
            $script:Gw.Records.Add([pscustomobject] @{ ZoneName = $record[0]
                    HostName = $record[1]; RecordType = 'A'
                    RecordData = [pscustomobject] @{ IPv4Address = $record[2] } })
        }
        $script:Done = [Collections.Generic.List[string]]::new()
    }

    function Get-NetIPAddress {
        [CmdletBinding()]
        param([string] $AddressFamily)
        return $script:Gw.Addresses
    }

    function Get-NetAdapter {
        [CmdletBinding()]
        param([int] $InterfaceIndex, [switch] $Physical)
        return @($script:Gw.Adapters | Where-Object {
                -not $PSBoundParameters.ContainsKey('InterfaceIndex') -or
                $_.InterfaceIndex -eq $InterfaceIndex })
    }

    function Get-DnsClient {
        param([int] $InterfaceIndex)
        return [pscustomobject] @{
            RegisterThisConnectionsAddress = $script:Gw.Register[$InterfaceIndex] }
    }

    function Set-DnsClient {
        param([int] $InterfaceIndex, [bool] $RegisterThisConnectionsAddress)
        $script:Done.Add("Set-DnsClient $InterfaceIndex $RegisterThisConnectionsAddress")
        $script:Gw.Register[$InterfaceIndex] = $RegisterThisConnectionsAddress
    }

    function Get-DnsClientServerAddress {
        param([int] $InterfaceIndex, [string] $AddressFamily)
        return [pscustomobject] @{ ServerAddresses = $script:Gw.Servers[$InterfaceIndex] }
    }

    function Set-DnsClientServerAddress {
        param([int] $InterfaceIndex, [string[]] $ServerAddresses)
        $script:Done.Add("Set-DnsClientServerAddress $InterfaceIndex $ServerAddresses")
        $script:Gw.Servers[$InterfaceIndex] = $ServerAddresses
    }

    function Get-CimInstance {
        param([string] $ClassName, [string] $Filter)
        [int] $index = $Filter -replace '^InterfaceIndex = ', ''
        return [pscustomobject] @{ Index = $index
            TcpipNetbiosOptions = $script:Gw.Netbios[$index] }
    }

    function Invoke-CimMethod {
        param([object] $InputObject, [string] $MethodName, [hashtable] $Arguments)
        $script:Done.Add("$MethodName $($InputObject.Index) $($Arguments.TcpipNetbiosOptions)")
        $script:Gw.Netbios[$InputObject.Index] = $Arguments.TcpipNetbiosOptions
    }

    function Get-NetConnectionProfile {
        [CmdletBinding()]
        param([int] $InterfaceIndex)
        return [pscustomobject] @{ NetworkCategory = $script:Gw.Category[$InterfaceIndex] }
    }

    function Set-NetConnectionProfile {
        param([int] $InterfaceIndex, [string] $NetworkCategory)
        $script:Done.Add("Set-NetConnectionProfile $InterfaceIndex $NetworkCategory")
        $script:Gw.Category[$InterfaceIndex] = $NetworkCategory
    }

    function Get-NetFirewallRule {
        [CmdletBinding()]
        param([string] $Name)
        if ($null -ne $script:Gw.Rule) {
            return $script:Gw.Rule
        }
    }

    function Get-NetFirewallInterfaceFilter {
        param([object] $AssociatedNetFirewallRule)
        return [pscustomobject] @{ InterfaceAlias = $AssociatedNetFirewallRule.Alias }
    }

    function Remove-NetFirewallRule {
        param([Parameter(ValueFromPipeline = $true)] [object] $InputObject)
        process {
            $script:Done.Add("Remove-NetFirewallRule $($InputObject.Name)")
            $script:Gw.Rule = $null
        }
    }

    function New-NetFirewallRule {
        param([string] $Name, [string] $DisplayName, [string] $Direction, [string] $Action,
            [Alias('Profile')] [string] $Profiles, [string] $InterfaceAlias, [string] $Enabled)
        $script:Done.Add("New-NetFirewallRule $Name $Direction $Action $Profiles $InterfaceAlias")
        $script:Gw.Rule = [pscustomobject] @{ Name = $Name; Enabled = $Enabled
            Direction = $Direction; Action = $Action; Profile = $Profiles; Alias = $InterfaceAlias }
    }

    function Get-Service {
        [CmdletBinding()]
        param([string] $Name)
        return $script:Gw.Services[$Name]
    }

    function Get-DnsServerSetting {
        param([switch] $All)
        return [pscustomobject] @{ ListeningIPAddress = $script:Gw.Listening }
    }

    function Set-DnsServerSetting {
        param([object] $InputObject)
        $script:Done.Add("Set-DnsServerSetting $($InputObject.ListeningIPAddress)")
        $script:Gw.Listening = @($InputObject.ListeningIPAddress)
    }

    function Restart-Service {
        param([string] $Name)
        $script:Done.Add("Restart-Service $Name")
    }

    function Get-DnsServerZone {
        return @($script:Gw.Zones | ForEach-Object {
                [pscustomobject] @{ ZoneName = $_; IsAutoCreated = $false; ZoneType = 'Primary'
                    IsReverseLookupZone = $_ -like '*.arpa' } })
    }

    function Get-DnsServerResourceRecord {
        param([string] $ZoneName)
        return @($script:Gw.Records | Where-Object { $_.ZoneName -eq $ZoneName })
    }

    function Remove-DnsServerResourceRecord {
        param([string] $ZoneName, [object] $InputObject, [switch] $Force)
        $script:Done.Add("Remove-DnsServerResourceRecord $ZoneName $($InputObject.HostName) " +
            $InputObject.RecordData.IPv4Address)
        $script:Gw.Records.Remove($InputObject) | Out-Null
    }

    function Get-WindowsFeature {
        param([string] $Name)
        return [pscustomobject] @{ Installed = $script:Gw.Routing }
    }

    function Install-WindowsFeature {
        param([string] $Name, [switch] $IncludeManagementTools)
        $script:Done.Add("Install-WindowsFeature $Name")
        $script:Gw.Routing = $true
    }

    function Install-RemoteAccess {
        param([string] $VpnType, [switch] $Confirm)
        $script:Done.Add("Install-RemoteAccess $VpnType")
        $script:Gw.Services.RemoteAccess = [pscustomobject] @{
            Status = 'Running'; StartType = 'Automatic' }
    }

    function Start-Service {
        param([string] $Name)
        $script:Done.Add("Start-Service $Name")
        $script:Gw.Services[$Name].Status = 'Running'
    }

    # netsh's routing ip nat context over the machine's NAT: its dump in the
    # script form netsh writes, install, and an interface added or set.
    function netsh {
        [string] $said = $args -join ' '
        $global:LASTEXITCODE = 0
        if ($said -eq 'routing ip nat dump') {
            if ($null -eq $script:Gw.Nat) {
                return
            }
            'pushd routing ip nat'
            'uninstall'
            'install'
            foreach ($name in $script:Gw.Nat.Keys) {
                "add interface name=`"$name`" mode=$($script:Gw.Nat[$name].ToUpperInvariant())"
            }
            'popd'
            return
        }
        $script:Done.Add("netsh $said")
        if ($said -eq 'routing ip nat install') {
            $script:Gw.Nat = [ordered] @{}
            return
        }
        if ($said -match '^routing ip nat (add|set) interface name=(.+) mode=(\w+)$') {
            $script:Gw.Nat[$Matches[2]] = $Matches[3]
        }
    }

    [string] $script:Name = $env:COMPUTERNAME
    $env:COMPUTERNAME = 'XMIP-DC01'
}

AfterAll {
    $env:COMPUTERNAME = $script:Name
}

Describe 'The environment file' {
    It 'gives a machine whose internet says so <Example>''s gateway machine' -ForEach @(
        @{ Example = 'hyperv' }, @{ Example = 'libvirt' }) {
        [hashtable] $read = Read-Environment -Made (New-Environment -Example $Example)
        $read.Gateway.machine.name | Should -Be 'XMIP-DC01'
        $read.Gateway.machine.address | Should -Be '10.77.0.10'
        $read.Gateway.uplink | Should -Be 'Uplink'
        $read.Common.network.uplink | Should -Be 'Uplink'
        $read.Common.network.enableNat | Should -BeFalse
        foreach ($machine in $read.Machines) {
            [string] $want = if ($machine['name'] -eq 'XMIP-RX01') { '10.77.0.10' } else { '' }
            $machine['network']['gateway'] | Should -Be $want -Because $machine['name']
            [string] $up = if ($machine['name'] -eq 'XMIP-DC01') { 'Uplink' } else { '' }
            $machine['network']['uplink'] | Should -Be $up -Because $machine['name']
        }
    }

    It 'leaves the host the gateway, through its NAT, where no gateway machine is named' {
        [hashtable] $read = Read-Environment -Made (New-Environment -Network @{
                gateway_machine = $null; uplink = $null; nat = $true })
        $read.Gateway | Should -BeNullOrEmpty
        $read.Common.network.uplink | Should -Be ''
        @($read.Machines | Where-Object { $_['network']['gateway'] } |
            ForEach-Object { "$($_['name']) $($_['network']['gateway'])" }) |
            Should -Be @('XMIP-RX01 10.77.0.1')
    }

    It 'refuses <Because>' -ForEach @(
        @{ Because = 'a gateway machine that is no Windows machine'
            Network = @{ gateway_machine = 'XMIP-RX01' }; Said = '*no Windows machine*' }
        @{ Because = 'a gateway machine the environment does not have'
            Network = @{ gateway_machine = 'XMIP-GW99' }; Said = '*no Windows machine*' }
        @{ Because = 'a gateway machine with no uplink'
            Network = @{ uplink = '' }; Said = '*write it in your copy*' }
        @{ Because = 'the host''s NAT beside a gateway machine'
            Network = @{ nat = $true }; Said = '*two ways out*' }
    ) {
        { Read-Environment -Made (New-Environment -Network $Network) } |
            Should -Throw -ExpectedMessage "REFUSED: $Said"
    }
}

Describe 'Where each technology makes the gateway' {
    It 'applies gateway.dsc.yaml after the domain''s controller and before the names' {
        [hashtable] $made = New-Environment
        [hashtable[]] $steps = @(Get-XmipTestDeployStep -Environment $made.Environment -Run (
                $made.Folder))
        [string[]] $named = @($steps | ForEach-Object { $_.Name })
        [int] $at = [array]::IndexOf($named, 'gateway')
        $at | Should -Be ([array]::IndexOf($named, 'domain-XMIP-DC01') + 1)
        $named[$at + 1] | Should -Be 'names'
        [hashtable] $value = $steps[$at].Value
        Split-Path -Path $steps[$at].Document -Leaf | Should -Be 'gateway.dsc.yaml'
        $value.machine.name | Should -Be 'XMIP-DC01'
        $value.prefix | Should -Be '10.77.0.0/24'
        $value.domain | Should -Be 'xmip.test'
        $value.common.secretPath | Should -Not -BeNullOrEmpty
        [Collections.IDictionary] $declared = (Read-XmipTestYaml -Path (
                $steps[$at].Document)).parameters
        @($declared.Keys | Where-Object { -not $value.ContainsKey($_) }) | Should -BeNullOrEmpty
    }

    It 'gives Xmip.Environment/Gateway every property its manifest requires' {
        [Collections.IDictionary] $resource = @((Read-XmipTestYaml -Path (
                    Join-Path $script:Environment 'gateway.dsc.yaml')).resources)[0]
        [Collections.IDictionary] $schema = (Read-XmipTestYaml -Path (Join-Path (
                    $script:Environment) 'xmip-environment-gateway.dsc.resource.yaml')).schema
        [string[]] $given = @($resource.properties.Keys)
        $schema.required | Where-Object { $_ -notin $given } | Should -BeNullOrEmpty
        $given | Where-Object { -not $schema.properties.Contains($_) } | Should -BeNullOrEmpty
    }

    It 'has no gateway step where no gateway machine is named' {
        [hashtable] $made = New-Environment -Network @{
            gateway_machine = $null; uplink = $null; nat = $true }
        @(Get-XmipTestDeployStep -Environment $made.Environment -Run $made.Folder |
            Where-Object { $_.Name -eq 'gateway' }) | Should -BeNullOrEmpty
    }

    It 'names the gateway machine in Ansible''s xmip_gateway, played before the names' {
        [hashtable] $made = New-Environment
        $made.Environment['technology'] = 'ansible'
        [string] $path = Write-XmipTestInventory -Environment $made.Environment -Run $made.Folder
        $children = (Read-XmipTestYaml -Path $path).all.children
        @($children.xmip_gateway.hosts.Keys) | Should -Be @('XMIP-DC01')
        $children.windows.hosts.Contains('XMIP-DC01') | Should -BeTrue
        $children.xmip_gateway.vars.xmip_network_prefix | Should -Be '10.77.0.0/24'
        $children.xmip_gateway.vars.xmip_gateway_script | Should -BeLike '*WindowsGateway.ps1'
        [string[]] $plays = @((Read-XmipTestYaml -Path (Join-Path $script:Root (
                        'deploy/dsc/ansible/environment.yml'))) | ForEach-Object { $_.hosts })
        [array]::IndexOf($plays, 'xmip_gateway') |
            Should -Be ([array]::IndexOf($plays, 'xmip_hypervisor_host') + 1)
        [array]::IndexOf($plays, 'xmip_name_server') |
            Should -Be ([array]::IndexOf($plays, 'xmip_gateway') + 1)
    }

    It 'hands <Script> whole to win_powershell in <Task>, written nowhere else' -ForEach @(
        @{ Script = 'WindowsGateway.ps1'; Task = 'xmip_gateway/tasks/main.yml'
            Rule = 'function Set-WindowsGateway\b' }
        @{ Script = 'HyperVUplink.ps1'; Task = 'xmip_machine/tasks/hyperv.yml'
            Rule = 'function Get-HyperVUplinkFinding\b' }
    ) {
        [string] $tasks = Get-Content -Raw -LiteralPath (
            Join-Path $script:Root "deploy/dsc/ansible/roles/$Task")
        $tasks | Should -Match ([regex]::Escape("lookup('ansible.builtin.file', xmip_"))
        $tasks | Should -Match ([regex]::Escape($Script) + '|xmip_gateway_script')
        [string] $deploy = Join-Path $script:Root 'deploy/dsc'
        [string[]] $holding = @(Get-ChildItem -Path $deploy -File -Recurse -Include '*.ps1',
            '*.yml', '*.yaml' | Where-Object {
                (Get-Content -Raw -LiteralPath $_.FullName) -match $Rule } |
            ForEach-Object { $_.Name })
        $holding | Should -Be @($Script)
    }
}

Describe 'The gateway machine, every Windows command a stub' {
    BeforeEach {
        Reset-FakeGateway
    }

    It 'finds a fresh machine differing in every rule, and changes nothing' {
        [string[]] $found = @(Get-WindowsGatewayFinding -Address '10.77.0.10' -Prefix (
                '10.77.0.0/24'))
        $found | Should -Be @(
            'Ethernet 2: registers its address in DNS.'
            # Promoting a domain controller leaves its adapter asking the
            # loopback, where a server listening on 10.77.0.10 alone answers
            # nothing.
            "Ethernet: asks the DNS servers '127.0.0.1', not '10.77.0.10'."
            "Ethernet 2: asks the DNS servers '192.0.2.1', not '10.77.0.10'."
            'Ethernet 2: NetBIOS over TCP/IP is not off.'
            'Ethernet 2: a Private network, not Public.'
            ('Ethernet 2: the inbound rule Xmip-Uplink-Inbound does not block everything ' +
                'arriving on it.')
            "The DNS server listens on '', not 10.77.0.10 alone."
            'The DNS record XMIP-DC01 of xmip.test holds 192.0.2.50.'
            'The DNS record @ of xmip.test holds 192.0.2.50.'
            'The DNS record gc of _msdcs.xmip.test holds 192.0.2.50.'
            'Routing, of Routing and Remote Access, is not installed.')
        $script:Done | Should -BeNullOrEmpty
    }

    It 'makes the machine the gateway, then finds it as it is and changes nothing more' {
        Set-WindowsGateway -Address '10.77.0.10' -Prefix '10.77.0.0/24' -Confirm:$false
        $script:Done | Should -Be @(
            'Set-DnsClient 7 False', 'SetTcpipNetbios 7 2', 'Set-NetConnectionProfile 7 Public'
            'New-NetFirewallRule Xmip-Uplink-Inbound Inbound Block Any Ethernet 2'
            'Set-DnsClientServerAddress 4 10.77.0.10', 'Set-DnsClientServerAddress 7 10.77.0.10'
            'Set-DnsServerSetting 10.77.0.10', 'Restart-Service DNS'
            'Remove-DnsServerResourceRecord xmip.test XMIP-DC01 192.0.2.50'
            'Remove-DnsServerResourceRecord xmip.test @ 192.0.2.50'
            'Remove-DnsServerResourceRecord _msdcs.xmip.test gc 192.0.2.50'
            'Install-WindowsFeature Routing', 'Install-RemoteAccess RoutingOnly'
            'netsh routing ip nat install'
            'netsh routing ip nat add interface name=Ethernet 2 mode=full'
            'netsh routing ip nat add interface name=Ethernet mode=private')
        # The network's own records stay: its address and every other machine's.
        @($script:Gw.Records | ForEach-Object { "$($_.HostName) $($_.RecordData.IPv4Address)" }) |
            Should -Be @('XMIP-DC01 10.77.0.10', '@ 10.77.0.10', 'RX1 10.77.0.41')
        Get-WindowsGatewayFinding -Address '10.77.0.10' -Prefix '10.77.0.0/24' |
            Should -BeNullOrEmpty
    }

    It 'sets a NAT interface in the wrong mode, and starts Routing that stopped' {
        Set-WindowsGateway -Address '10.77.0.10' -Prefix '10.77.0.0/24' -Confirm:$false
        $script:Gw.Nat['Ethernet 2'] = 'private'
        $script:Gw.Services.RemoteAccess.Status = 'Stopped'
        $script:Done.Clear()
        Get-WindowsGatewayFinding -Address '10.77.0.10' -Prefix '10.77.0.0/24' |
            Should -Be 'Routing and Remote Access is not running, started with the machine.'
        Set-WindowsGatewayNat -Adapter (Get-WindowsGatewayAdapter -Address '10.77.0.10')
        $script:Done | Should -Be @('Start-Service RemoteAccess',
            'netsh routing ip nat set interface name=Ethernet 2 mode=full')
    }

    It 'refuses a machine without its second adapter, changing nothing' {
        $script:Gw.Adapters = @($script:Gw.Adapters[0])
        Get-WindowsGatewayFinding -Address '10.77.0.10' -Prefix '10.77.0.0/24' |
            Should -Be '0 adapters beside the one holding 10.77.0.10, not one, the uplink.'
        { Set-WindowsGateway -Address '10.77.0.10' -Prefix '10.77.0.0/24' -Confirm:$false } |
            Should -Throw -ExpectedMessage 'REFUSED: 0 adapters beside*'
        $script:Done | Should -BeNullOrEmpty
    }

    It 'leaves the DNS server alone on a machine that runs none, the uplink asking as it does' {
        $script:Gw.Services.Remove('DNS')
        [string[]] $found = @(Get-WindowsGatewayFinding -Address '10.77.0.10' -Prefix (
                '10.77.0.0/24'))
        $found -like 'The DNS*' | Should -BeNullOrEmpty
        @($found -like '*asks the DNS servers*') |
            Should -Be @("Ethernet 2: asks the DNS servers '192.0.2.1', not '127.0.0.1'.")
    }

    It 'says a machine that is not Windows Server has no Routing and Remote Access' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'Get-WindowsFeature' }
        Get-WindowsGatewayNatFinding -Adapter (Get-WindowsGatewayAdapter -Address '10.77.0.10') |
            Should -Be 'Routing and Remote Access is not there: the machine is not Windows Server.'
    }

    It 'holds <Address> inside <Prefix>: <Inside>' -ForEach @(
        @{ Address = '10.77.0.10'; Prefix = '10.77.0.0/24'; Inside = $true }
        @{ Address = '10.77.1.10'; Prefix = '10.77.0.0/24'; Inside = $false }
        @{ Address = '10.77.1.10'; Prefix = '10.77.0.0/16'; Inside = $true }
        @{ Address = '192.0.2.50'; Prefix = '10.77.0.0/24'; Inside = $false }
        @{ Address = '2001:db8::5'; Prefix = '10.77.0.0/24'; Inside = $false }
    ) {
        Test-WindowsGatewayPrefix -Address $Address -Prefix $Prefix | Should -Be $Inside
    }
}

Describe 'Xmip.Environment/Gateway, the session a stub' {
    BeforeAll {
        # The session runs here: the one script, sent whole as its text.
        function Open-EnvironmentDomainSession {
            param([hashtable] $Instance)
            if ($script:Answering) {
                return [pscustomobject] @{ Name = $Instance.name }
            }
        }

        function Invoke-EnvironmentCommand {
            param([object] $Session, [scriptblock] $ScriptBlock, [object[]] $ArgumentList)
            $script:Sent = [string] $ScriptBlock
            & ([scriptblock]::Create([string] $ScriptBlock)) @ArgumentList
        }

        function Remove-PSSession {
            param([object] $Session)
        }

        [hashtable] $script:Instance = @{ name = 'XMIP-DC01'; address = '10.77.0.10'
            prefix = '10.77.0.0/24'; domain = 'xmip.test'; secretPath = 'secret.xml' }
    }

    BeforeEach {
        Reset-FakeGateway
        $script:Answering = $true
    }

    It 'answers a machine that does not answer as absent, never refused' {
        $script:Answering = $false
        [hashtable] $state = Get-EnvironmentGateway -Instance $script:Instance
        $state._exist | Should -BeFalse
        $state.answering | Should -BeFalse
        $state.findings | Should -Be @('XMIP-DC01: does not answer.')
        Set-EnvironmentGateway -Instance $script:Instance -Confirm:$false
        $script:Done | Should -BeNullOrEmpty
    }

    It 'runs WindowsGateway.ps1 in the session, makes the gateway, then finds it' {
        [hashtable] $state = Get-EnvironmentGateway -Instance $script:Instance
        $state._exist | Should -BeFalse
        $state.findings.Count | Should -Be 11
        $script:Sent | Should -Match '^param\(\$Address, \$Prefix\)'
        $script:Sent | Should -Match (
            'Get-WindowsGatewayFinding -Address \$Address -Prefix \$Prefix$')
        Set-EnvironmentGateway -Instance $script:Instance -Confirm:$false
        $script:Sent | Should -Match 'Set-WindowsGateway -Address \$Address -Prefix \$Prefix$'
        $state = Get-EnvironmentGateway -Instance $script:Instance
        $state._exist | Should -BeTrue
        $state.findings | Should -BeNullOrEmpty
        $state.answering | Should -BeTrue
    }
}
