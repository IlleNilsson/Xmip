# Native guest OS configuration runs in PowerShell Direct's built-in Windows
# endpoint. Xmip development tooling is invoked separately in PowerShell Core.
[CmdletBinding()]
[OutputType([pscustomobject])]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Get', 'Set')]
    [string] $Operation,

    [Parameter(Mandatory = $true)]
    [hashtable] $Lab,

    [Parameter(Mandatory = $true)]
    [hashtable] $Machine,

    [Parameter(Mandatory = $true)]
    [hashtable] $Secret
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') {
    throw 'Windows guest configuration requires Windows.'
}

function Get-LabGuestFinding {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    [object] $system = Get-CimInstance -ClassName Win32_ComputerSystem
    [object] $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($Machine.Role -eq 'Developer') {
        [string] $versionKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        [string] $release = (Get-ItemProperty -LiteralPath $versionKey).DisplayVersion
        if ($os.Caption -notlike '*Windows 11*' -or $release -ne '26H2') {
            Write-Output -InputObject 'Windows 11 26H2 is required.'
        }
    }
    elseif ($os.Caption -notlike '*Windows Server 2025*') {
        Write-Output -InputObject 'Windows Server 2025 is required.'
    }
    if ($system.Name -ne $Machine.Name) {
        Write-Output -InputObject 'Computer name differs or a rename reboot is pending.'
    }
    if ($system.Domain -ne $Lab.DomainName -or -not $system.PartOfDomain) {
        Write-Output -InputObject 'Domain membership differs.'
    }
    [object[]] $nics = @(Get-NetAdapter | Where-Object Status -eq 'Up')
    if ($nics.Count -ne 1) {
        Write-Output -InputObject 'Exactly one active network adapter is required.'
        return
    }
    [int] $index = $nics[0].ifIndex
    [object[]] $ips = @(Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4)
    if (@($ips | Where-Object {
        $_.IPAddress -eq $Machine.Address -and $_.PrefixLength -eq $Lab.Network.PrefixLength
    }).Count -ne 1) {
        Write-Output -InputObject 'Static IPv4 address differs.'
    }
    [hashtable] $routeQuery = @{
        InterfaceIndex = $index
        DestinationPrefix = '0.0.0.0/0'
        ErrorAction = 'SilentlyContinue'
    }
    [object[]] $routes = @(Get-NetRoute @routeQuery)
    if (@($routes | Where-Object NextHop -eq $Lab.Network.Gateway).Count -ne 1) {
        Write-Output -InputObject 'Default gateway differs.'
    }
    [string] $dcAddress = ($Lab.Machines | Where-Object Role -eq 'DomainController').Address
    [object] $dnsClient = Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily IPv4
    [string[]] $dns = $dnsClient.ServerAddresses
    if (($dns -join ',') -ne $dcAddress) {
        Write-Output -InputObject 'Domain DNS server differs.'
    }
}

function Get-LabRoleFinding {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    switch ($Machine.Role) {
        'DomainController' {
            if (-not (Get-WindowsFeature -Name AD-Domain-Services).Installed -or
                $null -eq (Get-Service -Name NTDS -ErrorAction SilentlyContinue)) {
                Write-Output -InputObject 'AD DS is not running.'
                return
            }
            if ((Get-ADDomain).DNSRoot -ne $Lab.DomainName) {
                Write-Output -InputObject 'Active Directory domain differs.'
            }
            [string[]] $forwarders = @((Get-DnsServerForwarder).IPAddress.IPAddressToString)
            [string[]] $expected = if ($Lab.Network.EnableNat) {
                @($Lab.Network.DnsForwarders)
            }
            else {
                @()
            }
            if (($forwarders -join ',') -ne ($expected -join ',')) {
                Write-Output -InputObject 'DNS forwarders differ.'
            }
            if ($null -eq (Get-ADGroup -Filter "Name -eq 'XmipLabUsers'")) {
                Write-Output -InputObject 'Lab file-share group is missing.'
            }
        }
        'FileServer' {
            [object] $share = Get-SmbShare -Name XmipLab -ErrorAction SilentlyContinue
            if ($null -eq $share -or $share.Path -ne 'C:\XmipLab\Share' -or
                -not $share.EncryptData) {
                Write-Output -InputObject 'Encrypted XmipLab SMB share is missing or differs.'
            }
        }
        'PostgreSql' {
            [object] $service = Get-Service -Name XmipPostgreSql -ErrorAction SilentlyContinue
            if ($null -eq $service -or $service.Status -ne 'Running') {
                Write-Output -InputObject 'PostgreSQL service is not running.'
                return
            }
            [string] $bin = "C:\Program Files\PostgreSQL\$($Lab.PostgreSql.MajorVersion)\bin"
            & "$bin\pg_isready.exe" -h 127.0.0.1 -p $Lab.PostgreSql.Port | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Output -InputObject 'PostgreSQL does not accept connections.'
            }
            [string] $config = 'C:\XmipLab\PostgreSql\postgresql.conf'
            [string] $hba = 'C:\XmipLab\PostgreSql\pg_hba.conf'
            if ((Get-Content -LiteralPath $config -Raw) -notmatch "listen_addresses = '\*'" -or
                (Get-Content -LiteralPath $hba -Raw) -notmatch
                [regex]::Escape("host all all $($Lab.Network.Prefix) scram-sha-256")) {
                Write-Output -InputObject 'PostgreSQL lab listener or access rule differs.'
            }
            [object] $firewall = Get-NetFirewallRule -Name XmipPostgreSql
            if ($firewall.Enabled -ne 'True') {
                Write-Output -InputObject 'PostgreSQL firewall rule is disabled.'
            }
            $env:PGPASSWORD = $Secret.PostgreSqlPassword.GetNetworkCredential().Password
            try {
                [string] $sql = "SELECT 1 FROM pg_database WHERE datname='$($Lab.PostgreSql.Database)'"
                [string[]] $connection = @('-U', 'postgres', '-h', '127.0.0.1',
                    '-p', [string] $Lab.PostgreSql.Port, '-d', 'postgres', '-tAc', $sql)
                [string] $exists = & "$bin\psql.exe" @connection
                if ($LASTEXITCODE -ne 0 -or $exists.Trim() -ne '1') {
                    Write-Output -InputObject 'Xmip test database is missing or authentication failed.'
                }
            }
            finally {
                Remove-Item -LiteralPath Env:PGPASSWORD -ErrorAction SilentlyContinue
            }
        }
        'Developer' {
            [string] $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
            if (-not (Test-Path -LiteralPath $pwsh)) {
                Write-Output -InputObject 'PowerShell Core is missing.'
                return
            }
            [string[]] $probe = @('-NoProfile', '-File',
                'C:\ProgramData\XmipLab\LabDevelopment.ps1', '-Operation', 'Get')
            & $pwsh @probe *> $null
            if ($LASTEXITCODE -ne 0) {
                Write-Output -InputObject 'Xmip developer prerequisites are missing or outdated.'
            }
        }
        'Xmip' {
            foreach ($leaf in @('bin', 'config', 'modules', 'data', 'logs')) {
                if (-not (Test-Path -LiteralPath "C:\ProgramData\Xmip\$leaf" -PathType Container)) {
                    Write-Output -InputObject "Xmip test directory is missing: $leaf"
                }
            }
        }
    }
}

function Set-LabGuestNetwork {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    [object[]] $nics = @(Get-NetAdapter | Where-Object Status -eq 'Up')
    if ($nics.Count -ne 1) {
        throw 'Prepared guests must have exactly one active network adapter.'
    }
    [int] $index = $nics[0].ifIndex
    Set-NetIPInterface -InterfaceIndex $index -AddressFamily IPv4 -Dhcp Disabled
    [object[]] $ips = @(Get-NetIPAddress -InterfaceIndex $index -AddressFamily IPv4)
    foreach ($ip in $ips) {
        if ($ip.IPAddress -ne $Machine.Address) {
            Remove-NetIPAddress -InputObject $ip -Confirm:$false
        }
    }
    if (@($ips | Where-Object IPAddress -eq $Machine.Address).Count -eq 0) {
        [hashtable] $ipCreate = @{
            InterfaceIndex = $index
            IPAddress = $Machine.Address
            PrefixLength = $Lab.Network.PrefixLength
        }
        New-NetIPAddress @ipCreate | Out-Null
    }
    [hashtable] $routeQuery = @{
        InterfaceIndex = $index
        DestinationPrefix = '0.0.0.0/0'
        ErrorAction = 'SilentlyContinue'
    }
    [object[]] $routes = @(Get-NetRoute @routeQuery)
    foreach ($route in $routes) {
        if ($route.NextHop -ne $Lab.Network.Gateway) {
            Remove-NetRoute -InputObject $route -Confirm:$false
        }
    }
    if (@($routes | Where-Object NextHop -eq $Lab.Network.Gateway).Count -eq 0) {
        [hashtable] $routeCreate = @{
            InterfaceIndex = $index
            DestinationPrefix = '0.0.0.0/0'
            NextHop = $Lab.Network.Gateway
        }
        New-NetRoute @routeCreate | Out-Null
    }
    [string] $dcAddress = ($Lab.Machines | Where-Object Role -eq 'DomainController').Address
    Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses $dcAddress
}

function Set-LabGuestRole {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    switch ($Machine.Role) {
        'DomainController' {
            Import-Module -Name ActiveDirectory
            [string[]] $forwarders = if ($Lab.Network.EnableNat) {
                @($Lab.Network.DnsForwarders)
            }
            else {
                @()
            }
            Set-DnsServerForwarder -IPAddress $forwarders -UseRootHint $false
            if ($null -eq (Get-ADGroup -Filter "Name -eq 'XmipLabUsers'")) {
                New-ADGroup -Name XmipLabUsers -GroupScope Global -GroupCategory Security
            }
        }
        'FileServer' {
            Install-WindowsFeature -Name FS-FileServer | Out-Null
            New-Item -Path C:\XmipLab\Share -ItemType Directory -Force | Out-Null
            [string] $users = "$($Lab.NetbiosName)\XmipLabUsers"
            [string] $admins = "$($Lab.NetbiosName)\Domain Admins"
            [string[]] $acl = @('C:\XmipLab\Share', '/inheritance:r', '/grant:r',
                '*S-1-5-18:(OI)(CI)F', "${admins}:(OI)(CI)F", "${users}:(OI)(CI)M")
            & icacls.exe @acl | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw 'Cannot configure file-share NTFS permissions.'
            }
            if ($null -eq (Get-SmbShare -Name XmipLab -ErrorAction SilentlyContinue)) {
                [hashtable] $shareCreate = @{
                    Name = 'XmipLab'
                    Path = 'C:\XmipLab\Share'
                    FullAccess = $admins
                    ChangeAccess = $users
                    EncryptData = $true
                }
                New-SmbShare @shareCreate | Out-Null
            }
            else {
                Set-SmbShare -Name XmipLab -EncryptData $true -Confirm:$false
            }
            [hashtable] $smbRule = @{
                Name = 'FPS-SMB-In-TCP'
                Enabled = 'True'
                RemoteAddress = $Lab.Network.Prefix
            }
            Set-NetFirewallRule @smbRule
        }
        'PostgreSql' {
            & C:\ProgramData\XmipLab\LabPostgreSql.ps1 -Lab $Lab -Secret $Secret
        }
        'Developer' {
            [string] $pwsh = 'C:\Program Files\PowerShell\7\pwsh.exe'
            if (-not (Test-Path -LiteralPath $pwsh)) {
                [hashtable] $install = @{
                    FilePath = 'msiexec.exe'
                    Wait = $true
                    PassThru = $true
                    ArgumentList = '/i C:\ProgramData\XmipLab\powershell.msi /qn /norestart'
                }
                [object] $process = Start-Process @install
                if ($process.ExitCode -notin @(0, 3010)) {
                    throw "PowerShell MSI failed: $($process.ExitCode)"
                }
            }
            [string[]] $installTools = @('-NoProfile', '-File',
                'C:\ProgramData\XmipLab\LabDevelopment.ps1', '-Operation', 'Set')
            & $pwsh @installTools *> $null
            if ($LASTEXITCODE -ne 0) {
                throw 'Developer setup failed; run LabDevelopment.ps1 interactively for details.'
            }
        }
        'Xmip' {
            foreach ($leaf in @('bin', 'config', 'modules', 'data', 'logs')) {
                New-Item -Path "C:\ProgramData\Xmip\$leaf" -ItemType Directory -Force | Out-Null
            }
        }
    }
}

if ($Operation -eq 'Set') {
    [object] $system = Get-CimInstance -ClassName Win32_ComputerSystem
    [object] $os = Get-CimInstance -ClassName Win32_OperatingSystem
    if (($Machine.Role -eq 'Developer' -and $os.Caption -notlike '*Windows 11*') -or
        ($Machine.Role -ne 'Developer' -and $os.Caption -notlike '*Windows Server 2025*')) {
        throw 'REFUSED: guest OS does not match the configured role.'
    }
    Set-LabGuestNetwork
    if ($system.Name -ne $Machine.Name) {
        Rename-Computer -NewName $Machine.Name -Force | Out-Null
        & shutdown.exe /r /t 5 | Out-Null
        return [pscustomobject] @{ Ready = $false; Findings = @('Rename reboot pending.') }
    }
    if (-not $system.PartOfDomain) {
        if ($Machine.Role -eq 'DomainController') {
            Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
            [hashtable] $promote = @{
                DomainName = $Lab.DomainName
                DomainNetbiosName = $Lab.NetbiosName
                SafeModeAdministratorPassword = $Secret.DsrmPassword.Password
                InstallDns = $true
                NoRebootOnCompletion = $true
                Force = $true
            }
            Install-ADDSForest @promote | Out-Null
        }
        else {
            Add-Computer -DomainName $Lab.DomainName -Credential $Secret.DomainAdministrator |
                Out-Null
        }
        & shutdown.exe /r /t 5 | Out-Null
        return [pscustomobject] @{ Ready = $false; Findings = @('Domain reboot pending.') }
    }
    if ($system.Domain -ne $Lab.DomainName) {
        throw 'REFUSED: guest is already joined to a different domain.'
    }
    Set-LabGuestRole
}
[string[]] $findings = @(Get-LabGuestFinding) + @(Get-LabRoleFinding)
return [pscustomobject] @{ Ready = $findings.Count -eq 0; Findings = $findings }
