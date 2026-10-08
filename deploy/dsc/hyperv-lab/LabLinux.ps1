#requires -PSEdition Core
#requires -Version 7.6.5
# The lab's AlmaLinux guests on the host: the account and key the kickstart
# gives each (LabAnswer.ps1), and the parameters the guest's own DSC document
# is given. The VM itself is LabMachine.ps1's, as every machine's is.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The account the kickstart creates on every Linux guest; key-only, sudo
# without a password, the one way in.
$script:LabLinuxUser = 'xmiplab'

function Get-LabLinuxHostName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    return $Machine.Name.ToLowerInvariant()
}

function Get-LabPublicKey {
    <#
    .SYNOPSIS
    The lab's SSH public key as a kickstart takes it: its type and key, no comment.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab
    )

    [string] $path = "$($Lab.SshKeyPath).pub"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "The lab's SSH key is missing; run Initialize-LabCredential.ps1 first: $path"
    }
    [string[]] $fields = @((Get-Content -LiteralPath $path -Raw).Trim() -split '\s+')
    if ($fields.Count -lt 2 -or $fields[0] -ne 'ssh-ed25519' -or
        $fields[1] -notmatch '^[A-Za-z0-9+/=]+$') {
        throw "Not an ed25519 public key: $path"
    }
    return "$($fields[0]) $($fields[1])"
}

function Get-LabReplicationSlot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    return (Get-LabLinuxHostName -Machine $Machine) -replace '[^a-z0-9]', '_'
}

function Get-LabLinuxGuestParameter {
    <#
    .SYNOPSIS
    What one Linux guest's DSC document is given: no secret, nothing it could
    not be told in the clear.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [hashtable] $controller = $Lab.Machines | Where-Object Role -eq 'DomainController'
    [string] $hostName = Get-LabLinuxHostName -Machine $Machine
    [hashtable] $parameter = @{
        Name = $Machine.Name
        HostName = $hostName
        Address = $Machine.Address
        PrefixLength = $Lab.Network.PrefixLength
        Gateway = $Lab.Network.Gateway
        NetworkPrefix = $Lab.Network.Prefix
        Dns = $controller.Address
        DomainController = "$($controller.Name.ToLowerInvariant()).$($Lab.DomainName)"
        Role = $Machine.Role
    }
    if ($Machine.Role -eq 'PostgreSql') {
        $parameter.PostgreSql = Get-LabPostgreSqlParameter -Lab $Lab -Machine $Machine
    }
    if ($Machine.Role -eq 'Xmip') {
        $parameter.Xmip = @{ Node = $Machine.Name }
    }
    return $parameter
}

function Get-LabPostgreSqlParameter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [hashtable] $primary = $null
    if ($Machine.ContainsKey('StandbyOf')) {
        [hashtable] $source = $Lab.Machines | Where-Object Name -eq $Machine.StandbyOf
        $primary = @{
            Fqdn = "$(Get-LabLinuxHostName -Machine $source).$($Lab.DomainName)"
            Slot = Get-LabReplicationSlot -Machine $Machine
        }
    }
    [object[]] $standbys = @($Lab.Machines | Where-Object {
        $_.ContainsKey('StandbyOf') -and $_.StandbyOf -eq $Machine.Name
    } | ForEach-Object {
        @{ Address = $_.Address; Slot = Get-LabReplicationSlot -Machine $_ }
    })
    return @{
        MajorVersion = $Lab.PostgreSql.MajorVersion
        Port = $Lab.PostgreSql.Port
        Primary = $primary
        Standbys = $standbys
    }
}
