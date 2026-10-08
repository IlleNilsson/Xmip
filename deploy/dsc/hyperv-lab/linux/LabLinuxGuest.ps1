#requires -PSEdition Core
#requires -Version 7.6.5
<#
.SYNOPSIS
DSC v3 command resource for one AlmaLinux guest of the Xmip Hyper-V lab.
.DESCRIPTION
DSC hands the desired state on standard input, {"Machine": {...}}, as the host
composed it (Get-LabLinuxGuestParameter). Get and Test report real findings;
Set changes the guest and reports what is left. The network is cloud-init's
and is only checked here. A secret is read from /run/xmip-lab/secret.json,
which the host writes for one Set run and removes after it.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
[OutputType([string])]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Get', 'Test', 'Set')]
    [string] $Operation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'LabPostgreSql.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'LabPostgreSqlSetup.ps1')

function Invoke-LabNative {
    <#
    .SYNOPSIS
    Runs a program that must succeed, and returns its standard output lines.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [string[]] $ArgumentList,

        [AllowNull()]
        [string] $InputText
    )

    [string[]] $output = if ([string]::IsNullOrEmpty($InputText)) {
        @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { [string] $_ })
    }
    else {
        @($InputText | & $FilePath @ArgumentList 2>&1 | ForEach-Object { [string] $_ })
    }
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath $($ArgumentList[0]) failed: $($output -join ' ')"
    }
    return $output
}

function Get-LabGuestFinding {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [string] $release = Get-Content -LiteralPath /etc/os-release -Raw
    if ($release -notmatch '(?m)^ID="?almalinux"?$' -or
        $release -notmatch '(?m)^VERSION_ID="?10(\.\d+)?"?$') {
        Write-Output -InputObject 'AlmaLinux 10 is required.'
    }
    if ((& hostname -s) -ne $Machine.HostName) {
        Write-Output -InputObject 'Host name differs from the seed.'
    }
    [string] $addresses = (& ip -4 -o address show) -join "`n"
    if ($addresses -notmatch [regex]::Escape(" $($Machine.Address)/$($Machine.PrefixLength) ")) {
        Write-Output -InputObject 'Static IPv4 address differs.'
    }
    if (((& ip -4 route show default) -join ' ') -notmatch
        [regex]::Escape("via $($Machine.Gateway) ")) {
        Write-Output -InputObject 'Default gateway differs.'
    }
    [string[]] $servers = @(Get-Content -LiteralPath /etc/resolv.conf |
        Where-Object { $_ -match '^nameserver\s' } | ForEach-Object { ($_ -split '\s+')[1] })
    if (($servers -join ',') -ne $Machine.Dns) {
        Write-Output -InputObject 'Domain DNS server differs.'
    }
    & getent hosts $Machine.DomainController | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output -InputObject "Domain DNS does not resolve $($Machine.DomainController)."
    }
    if ((& systemctl is-active firewalld) -ne 'active') {
        Write-Output -InputObject 'firewalld is not running.'
    }
}

function Set-LabGuestBase {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if ($null -eq (Get-Command -Name firewall-cmd -ErrorAction Ignore)) {
        Invoke-LabNative -FilePath dnf -ArgumentList @('install', '-y', 'firewalld') | Out-Null
    }
    Invoke-LabNative -FilePath systemctl -ArgumentList @('enable', '--now', 'firewalld') |
        Out-Null
}

function Invoke-LabXmipNode {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Get', 'Set')]
        [string] $Operation,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [hashtable] $node = @{
        Operation = $Operation
        Root = '/opt/xmip'
        Payload = Join-Path -Path $PSScriptRoot -ChildPath 'xmip'
        Executable = 'xmip-service'
        Node = $Machine.Xmip.Node
    }
    & (Join-Path -Path $PSScriptRoot -ChildPath 'LabXmipNode.ps1') @node
}

function Get-LabRoleFinding {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    switch ($Machine.Role) {
        'PostgreSql' {
            Get-LabPostgreSqlFinding -Machine $Machine
        }
        'Xmip' {
            Invoke-LabXmipNode -Operation Get -Machine $Machine
        }
        default {
            Write-Output -InputObject "No Linux configuration exists for the role $($Machine.Role)."
        }
    }
}

try {
    [hashtable] $desired = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
    [hashtable] $machine = $desired.Machine
    if (-not $IsLinux) {
        throw 'This resource configures a Linux guest of the lab.'
    }
    if ($Operation -eq 'Set' -and $PSCmdlet.ShouldProcess($machine.Name, 'Configure lab guest')) {
        [string] $secretPath = '/run/xmip-lab/secret.json'
        [hashtable] $secret = if (Test-Path -LiteralPath $secretPath -PathType Leaf) {
            Get-Content -LiteralPath $secretPath -Raw | ConvertFrom-Json -AsHashtable
        }
        else {
            @{}
        }
        Set-LabGuestBase
        if ($machine.Role -eq 'PostgreSql') {
            Set-LabPostgreSql -Machine $machine -Secret $secret
        }
        if ($machine.Role -eq 'Xmip') {
            Invoke-LabXmipNode -Operation Set -Machine $machine | Out-Null
        }
    }
    [string[]] $findings = @(Get-LabGuestFinding -Machine $machine) +
        @(Get-LabRoleFinding -Machine $machine)
    [hashtable] $state = @{
        Machine = $machine
        Findings = @($findings)
        _inDesiredState = $findings.Count -eq 0
    }
    $state | ConvertTo-Json -Depth 10 -Compress
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
