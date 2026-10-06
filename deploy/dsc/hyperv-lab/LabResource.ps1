#requires -PSEdition Core
#requires -Version 7.6.5
<#
.SYNOPSIS
Command-resource boundary for the lab's host and Windows guest fleet.
.DESCRIPTION
DSC invokes Get, Test or Set with JSON on stdin. Only Set mutates. Returns real
findings, including pending first boot and reboots, rather than success markers.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
[OutputType([string])]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Get', 'Test', 'Set')]
    [string] $Operation,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Host', 'Guests')]
    [string] $Scope
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'LabHost.ps1')

function Open-LabGuestSession {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.PSSession])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [hashtable] $Credential
    )

    foreach ($account in @($Credential.LocalAdministrator, $Credential.DomainAdministrator)) {
        try {
            return New-PSSession -VMName $Name -Credential $account -ErrorAction Stop
        }
        catch {
            # Local Administrator ceases to be a local identity after DC promotion.
            continue
        }
    }
    return $null
}

function Copy-LabGuestPayload {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    Invoke-Command -Session $Session -ScriptBlock {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        New-Item -Path C:\ProgramData\XmipLab -ItemType Directory -Force | Out-Null
        [string[]] $acl = @('C:\ProgramData\XmipLab', '/inheritance:r', '/grant:r',
            '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F')
        & icacls.exe @acl | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Cannot restrict the guest payload directory.'
        }
    } | Out-Null
    if ($Machine.Role -eq 'PostgreSql') {
        [hashtable] $copy = @{
            LiteralPath = $Lab.PostgreSql.Installer
            ToSession = $Session
            Destination = 'C:\ProgramData\XmipLab\postgresql.exe'
            Force = $true
        }
        Copy-Item @copy
        [string] $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'LabPostgreSql.ps1'
        $copy.LiteralPath = $scriptPath
        $copy.Destination = 'C:\ProgramData\XmipLab\LabPostgreSql.ps1'
        Copy-Item @copy
    }
    if ($Machine.Role -eq 'Developer') {
        [hashtable] $copy = @{
            LiteralPath = $Lab.Development.PowerShellMsi
            ToSession = $Session
            Destination = 'C:\ProgramData\XmipLab\powershell.msi'
            Force = $true
        }
        Copy-Item @copy
        [string] $scriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'LabDevelopment.ps1'
        $copy.LiteralPath = $scriptPath
        $copy.Destination = 'C:\ProgramData\XmipLab\LabDevelopment.ps1'
        Copy-Item @copy
        Invoke-Command -Session $Session -ScriptBlock {
            New-Item -Path C:\ProgramData\XmipLab\Estate -ItemType Directory -Force | Out-Null
        } | Out-Null
        [string] $tooling = Join-Path -Path $Lab.Development.RepositoryRoot -ChildPath 'Xmip'
        $copy.LiteralPath = $tooling
        $copy.Destination = 'C:\ProgramData\XmipLab\Estate'
        Copy-Item @copy -Recurse
        [string] $manifest = Join-Path -Path $Lab.Development.RepositoryRoot -ChildPath
            'prerequisite.toml'
        $copy.LiteralPath = $manifest
        $copy.Destination = 'C:\ProgramData\XmipLab\Estate\prerequisite.toml'
        Copy-Item @copy
    }
}

function Get-LabFleetFinding {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Credential,

        [switch] $Configure
    )

    [string] $guestPath = Join-Path -Path $PSScriptRoot -ChildPath 'LabGuest.ps1'
    [scriptblock] $guest = [scriptblock]::Create((Get-Content -LiteralPath $guestPath -Raw))
    [object[]] $ordered = @($Lab.Machines | Sort-Object {
        if ($_.Role -eq 'DomainController') { 0 } else { 1 }
    })
    [bool] $dcReady = $false
    foreach ($machine in $ordered) {
        if ($machine.Role -ne 'DomainController' -and -not $dcReady) {
            Write-Output -InputObject "$($machine.Name): waiting for the domain controller."
            continue
        }
        [object] $vm = Get-VM -Name $machine.Name -ErrorAction SilentlyContinue
        if ($null -eq $vm -or $vm.Notes -ne $Lab.LabId) {
            throw "REFUSED: $($machine.Name) is missing or not owned by this lab."
        }
        [object] $session = Open-LabGuestSession -Name $machine.Name -Credential $Credential
        if ($null -eq $session) {
            Write-Output -InputObject "$($machine.Name): PowerShell Direct unavailable or login failed."
            continue
        }
        try {
            [hashtable] $invoke = @{
                Session = $session
                ScriptBlock = $guest
                ArgumentList = @('Get', $Lab, $machine, $Credential)
            }
            [object] $result = Invoke-Command @invoke
            if ($Configure -and -not $result.Ready) {
                Copy-LabGuestPayload -Session $session -Lab $Lab -Machine $machine
                $invoke.ArgumentList = @('Set', $Lab, $machine, $Credential)
                $result = Invoke-Command @invoke
            }
            if ($machine.Role -eq 'DomainController') {
                $dcReady = $result.Ready
            }
            foreach ($finding in $result.Findings) {
                Write-Output -InputObject "$($machine.Name): $finding"
            }
        }
        finally {
            Remove-PSSession -Session $session
        }
    }
}

try {
    [hashtable] $inputState = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
    [hashtable] $lab = Read-LabConfiguration -Path $inputState.ConfigPath
    if (-not $IsWindows) {
        throw 'Hyper-V provisioning requires a Windows host; configuration validation is portable.'
    }
    if ($Scope -eq 'Host') {
        if ($Operation -eq 'Set' -and $PSCmdlet.ShouldProcess($lab.LabId, 'Provision Hyper-V lab')) {
            Assert-LabMedia -Lab $lab
            Set-LabNetwork -Lab $lab -Confirm:$false
            foreach ($machine in $lab.Machines) {
                Set-LabVirtualMachine -Lab $lab -Machine $machine -Confirm:$false
            }
        }
        [string[]] $findings = @(Get-LabHostFinding -Lab $lab)
    }
    else {
        [hashtable] $credential = Import-Clixml -LiteralPath $lab.CredentialPath
        # Wrap secure strings as PSCredentials for remoting serialization.
        $credential.DsrmPassword = [pscredential]::new('dsrm', $credential.DsrmPassword)
        $credential.PostgreSqlPassword = [pscredential]::new('postgres',
            $credential.PostgreSqlPassword)
        $credential.DomainAdministrator = [pscredential]::new(
            "$($lab.NetbiosName)\Administrator", $credential.LocalAdministrator.Password)
        [bool] $configure = $Operation -eq 'Set' -and
            $PSCmdlet.ShouldProcess($lab.LabId, 'Configure Windows guest fleet')
        [hashtable] $fleet = @{ Lab = $lab; Credential = $credential; Configure = $configure }
        [string[]] $findings = @(Get-LabFleetFinding @fleet)
    }
    [hashtable] $state = @{
        ConfigPath = $inputState.ConfigPath
        _inDesiredState = $findings.Count -eq 0
        Findings = @($findings)
    }
    $state | ConvertTo-Json -Depth 10 -Compress
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
