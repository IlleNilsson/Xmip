#requires -PSEdition Core
#requires -Version 7.6.5
# Host-only operations are guarded at the resource boundary. Hyper-V has no
# cross-platform equivalent; the DSC protocol and validation remain portable.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The operating systems a machine may run: each one's family, the roles it may
# carry, the least memory and disk its installer accepts, its Secure Boot
# template, and whether it needs a virtual TPM. A machine's family comes from
# its Os, never from its name.
$script:LabOs = @{
    WindowsServer2025 = @{
        Family = 'Windows'
        Roles = @('DomainController', 'FileServer', 'Xmip')
        MinimumMemoryGB = 2
        MinimumDiskGB = 32
        SecureBootTemplate = 'MicrosoftWindows'
        Tpm = $false
    }
    Windows11 = @{
        Family = 'Windows'
        Roles = @('Developer')
        MinimumMemoryGB = 4
        MinimumDiskGB = 64
        SecureBootTemplate = 'MicrosoftWindows'
        Tpm = $true
    }
    AlmaLinux10 = @{
        Family = 'Linux'
        Roles = @('PostgreSql', 'Xmip')
        MinimumMemoryGB = 2
        MinimumDiskGB = 20
        SecureBootTemplate = 'MicrosoftUEFICertificateAuthority'
        Tpm = $false
    }
}

function Read-LabConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [hashtable] $lab = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if ($lab.LabId -notmatch '^[A-Za-z0-9-]+$') {
        throw 'LabId must contain only letters, digits and hyphens.'
    }
    if ($lab.DomainName -notmatch '^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$') {
        throw 'Use a fully qualified lab domain name.'
    }
    if ($lab.NetbiosName -notmatch '^[A-Za-z][A-Za-z0-9-]{0,14}$') {
        throw 'NetbiosName must be a valid domain NetBIOS name.'
    }
    # Enumerated, not member-accessed: an array's own Address method would win.
    [string[]] $names = @($lab.Machines | ForEach-Object { $_.Name })
    [string[]] $addresses = @($lab.Machines | ForEach-Object { $_.Address }) +
        $lab.Network.Gateway
    if (@($names | Select-Object -Unique).Count -ne $names.Count -or
        @($addresses | Select-Object -Unique).Count -ne $addresses.Count) {
        throw 'Machine names and addresses must be unique.'
    }
    foreach ($machine in $lab.Machines) {
        Assert-LabMachine -Lab $lab -Machine $machine
        $machine.Family = $script:LabOs[$machine.Os].Family
    }
    [object[]] $controllers = @($lab.Machines | Where-Object Role -eq 'DomainController')
    if ($controllers.Count -ne 1 -or $controllers[0].Family -ne 'Windows') {
        throw 'Exactly one Windows domain controller is required.'
    }
    Assert-LabAddress -Lab $lab -Address $addresses
    foreach ($os in @($lab.Images.Keys)) {
        if (-not $script:LabOs.ContainsKey($os) -or $script:LabOs[$os].Family -ne 'Windows') {
            continue
        }
        if (-not $lab.Images[$os].ContainsKey('Edition') -or
            [string]::IsNullOrWhiteSpace($lab.Images[$os].Edition)) {
            throw "$os needs its Edition: the name of the image on its ISO to install."
        }
    }
    [string[]] $paths = @($lab.Root, $lab.CredentialPath, $lab.SshKeyPath) +
        @($lab.Images.Values | ForEach-Object { $_.Path })
    foreach ($path in $paths) {
        if (-not [IO.Path]::IsPathFullyQualified($path)) {
            throw "Lab paths must be absolute: $path"
        }
    }
    return $lab
}

function Assert-LabMachine {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    if ($Machine.Name -notmatch '^[A-Za-z][A-Za-z0-9-]{0,14}$' -or $Machine.Cpu -lt 1) {
        throw "Invalid machine name or size: $($Machine.Name)"
    }
    if (-not $script:LabOs.ContainsKey([string] $Machine.Os) -or
        -not $Lab.Images.ContainsKey([string] $Machine.Os)) {
        throw "$($Machine.Name): Os must be one of the lab's images."
    }
    [hashtable] $os = $script:LabOs[$Machine.Os]
    if ($Machine.MemoryGB -lt $os.MinimumMemoryGB -or -not $Machine.ContainsKey('DiskGB') -or
        $Machine.DiskGB -lt $os.MinimumDiskGB) {
        [string] $least = "$($os.MinimumMemoryGB) GB of memory and $($os.MinimumDiskGB) GB of disk"
        throw "$($Machine.Name): $($Machine.Os) installs with $least at least."
    }
    if ($Machine.Role -notin $os.Roles) {
        throw "$($Machine.Name): $($Machine.Os) carries only $($os.Roles -join ', ')."
    }
    if ($Machine.ContainsKey('StandbyOf')) {
        [object[]] $primary = @($Lab.Machines | Where-Object {
            $_.Name -eq $Machine.StandbyOf -and $_.Role -eq 'PostgreSql' -and
            -not $_.ContainsKey('StandbyOf')
        })
        if ($Machine.Role -ne 'PostgreSql' -or $primary.Count -ne 1) {
            throw "$($Machine.Name): StandbyOf names no PostgreSQL primary."
        }
    }
}

function Assert-LabAddress {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [string[]] $Address
    )

    # Restrict the first version to /24; all IPs must belong to that subnet.
    if ($Lab.Network.Prefix -notmatch '^(\d+\.\d+\.\d+)\.0/24$' -or
        $Lab.Network.PrefixLength -ne 24) {
        throw 'This lab supports an IPv4 /24 subnet only.'
    }
    [string] $networkBase = $Matches[1]
    foreach ($candidate in $Address) {
        [ipaddress] $parsed = [ipaddress]::Parse($candidate)
        if ($parsed.AddressFamily -ne 'InterNetwork' -or
            $candidate -notlike "$networkBase.*" -or
            $parsed.GetAddressBytes()[3] -in @(0, 255)) {
            throw "Address outside the lab subnet: $candidate"
        }
    }
}

function Get-LabMacAddress {
    <#
    .SYNOPSIS
    The static MAC a lab guest is given: Hyper-V's prefix 00-15-5D and the last
    three octets of its address, so a kickstart can match its adapter by MAC.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Address
    )

    [byte[]] $bytes = ([ipaddress]::Parse($Address)).GetAddressBytes()
    return '00155D{0:X2}{1:X2}{2:X2}' -f $bytes[1], $bytes[2], $bytes[3]
}

function Get-LabHostFinding {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab
    )

    if ($null -eq (Get-Command -Name Get-VM -ErrorAction SilentlyContinue)) {
        return 'Hyper-V is not enabled; enable the host feature and reboot first.'
    }
    [object] $switch = Get-VMSwitch -Name $Lab.Network.SwitchName -ErrorAction SilentlyContinue
    if ($null -eq $switch -or $switch.SwitchType -ne 'Internal' -or
        $switch.Notes -ne $Lab.LabId) {
        Write-Output -InputObject 'Internal lab switch is missing or does not match.'
    }
    [string] $alias = "vEthernet ($($Lab.Network.SwitchName))"
    [hashtable] $ipQuery = @{
        InterfaceAlias = $alias
        AddressFamily = 'IPv4'
        ErrorAction = 'SilentlyContinue'
    }
    [object[]] $ips = @(Get-NetIPAddress @ipQuery)
    if (@($ips | Where-Object {
        $_.IPAddress -eq $Lab.Network.Gateway -and $_.PrefixLength -eq 24
    }).Count -ne 1) {
        Write-Output -InputObject 'Lab host gateway is missing.'
    }
    [object] $nat = Get-NetNat -Name $Lab.LabId -ErrorAction SilentlyContinue
    if ($Lab.Network.EnableNat -and ($null -eq $nat -or
        $nat.InternalIPInterfaceAddressPrefix -ne $Lab.Network.Prefix)) {
        Write-Output -InputObject 'Outbound NAT is missing or differs.'
    }
    if (-not $Lab.Network.EnableNat -and $null -ne $nat) {
        Write-Output -InputObject 'NAT exists although the lab requests isolation.'
    }
    foreach ($machine in @($Lab.Machines | Where-Object Family -eq 'Windows')) {
        Get-LabVirtualMachineFinding -Lab $Lab -Machine $machine
    }
}

function Set-LabNetwork {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab
    )

    [object] $switch = Get-VMSwitch -Name $Lab.Network.SwitchName -ErrorAction SilentlyContinue
    if ($null -ne $switch -and ($switch.Notes -ne $Lab.LabId -or
        $switch.SwitchType -ne 'Internal')) {
        throw 'REFUSED: the switch name belongs to a different configuration.'
    }
    if (-not $PSCmdlet.ShouldProcess($Lab.Network.SwitchName, 'Configure lab networking')) {
        return
    }
    if ($null -eq $switch) {
        New-VMSwitch -Name $Lab.Network.SwitchName -SwitchType Internal | Out-Null
        Set-VMSwitch -Name $Lab.Network.SwitchName -Notes $Lab.LabId
    }
    [string] $alias = "vEthernet ($($Lab.Network.SwitchName))"
    [hashtable] $ipQuery = @{
        InterfaceAlias = $alias
        AddressFamily = 'IPv4'
        ErrorAction = 'SilentlyContinue'
    }
    [object[]] $ips = @(Get-NetIPAddress @ipQuery)
    if (@($ips | Where-Object IPAddress -eq $Lab.Network.Gateway).Count -eq 0) {
        if (@($ips | Where-Object IPAddress -NotLike '169.254.*').Count -gt 0) {
            throw 'REFUSED: the switch already has a different static host address.'
        }
        [hashtable] $gateway = @{
            InterfaceAlias = $alias
            IPAddress = $Lab.Network.Gateway
            PrefixLength = 24
        }
        New-NetIPAddress @gateway | Out-Null
    }
    [object] $nat = Get-NetNat -Name $Lab.LabId -ErrorAction SilentlyContinue
    if ($null -ne $nat -and ($nat.InternalIPInterfaceAddressPrefix -ne $Lab.Network.Prefix -or
        -not $Lab.Network.EnableNat)) {
        throw 'REFUSED: NAT differs; resolve it explicitly before running DSC.'
    }
    if ($Lab.Network.EnableNat -and $null -eq $nat) {
        if (@(Get-NetNat).Count -gt 0) {
            throw 'REFUSED: another host NAT exists; choose an isolated lab or resolve it first.'
        }
        New-NetNat -Name $Lab.LabId -InternalIPInterfaceAddressPrefix $Lab.Network.Prefix |
            Out-Null
    }
}
