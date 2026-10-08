#requires -PSEdition Core
#requires -Version 7.6.5
<#
.SYNOPSIS
Command-resource boundary for the lab's host, Windows guests and Linux guests.
.DESCRIPTION
DSC invokes Get, Test or Set with JSON on stdin; xmip-lab.dsc.manifests.json
names the three resources. Only Set mutates. Returns real findings, including
pending first boot and reboots, rather than success markers.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
[OutputType([string])]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Get', 'Test', 'Set')]
    [string] $Operation,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Host', 'WindowsGuests', 'LinuxGuests')]
    [string] $Scope
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'LabHost.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'LabLinux.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'LabMedia.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'LabLinuxFleet.ps1')

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

function Copy-LabGuestFile {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(Mandatory = $true)]
        [string] $LiteralPath,

        [Parameter(Mandatory = $true)]
        [string] $Destination
    )

    [hashtable] $copy = @{
        LiteralPath = $LiteralPath
        ToSession = $Session
        Destination = $Destination
        Force = $true
        Recurse = (Test-Path -LiteralPath $LiteralPath -PathType Container)
    }
    Copy-Item @copy
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
        foreach ($directory in @('C:\ProgramData\XmipLab', 'C:\ProgramData\XmipLab\Xmip',
            'C:\ProgramData\XmipLab\Estate')) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        [string[]] $acl = @('C:\ProgramData\XmipLab', '/inheritance:r', '/grant:r',
            '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F')
        & icacls.exe @acl | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Cannot restrict the guest payload directory.'
        }
    } | Out-Null
    [hashtable] $files = @{}
    if ($Machine.Role -eq 'Xmip') {
        $files['C:\ProgramData\XmipLab\LabXmipNode.ps1'] =
            Join-Path -Path $PSScriptRoot -ChildPath 'LabXmipNode.ps1'
        $files['C:\ProgramData\XmipLab\Xmip\xmip.toml'] = $Lab.Xmip.Cluster
        $files['C:\ProgramData\XmipLab\Xmip\xmip-service.exe'] = $Lab.Xmip.WindowsService
    }
    if ($Machine.Role -eq 'Developer') {
        [string] $root = $Lab.Development.RepositoryRoot
        $files['C:\ProgramData\XmipLab\powershell.msi'] = $Lab.Development.PowerShellMsi
        $files['C:\ProgramData\XmipLab\LabDevelopment.ps1'] =
            Join-Path -Path $PSScriptRoot -ChildPath 'LabDevelopment.ps1'
        $files['C:\ProgramData\XmipLab\Estate'] = Join-Path -Path $root -ChildPath 'Xmip'
        $files['C:\ProgramData\XmipLab\Estate\prerequisite.toml'] =
            Join-Path -Path $root -ChildPath 'prerequisite.toml'
    }
    foreach ($destination in $files.Keys) {
        [string] $source = $files[$destination]
        Copy-LabGuestFile -Session $Session -LiteralPath $source -Destination $destination
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
    [object[]] $ordered = @($Lab.Machines | Where-Object Family -eq 'Windows' | Sort-Object {
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
            [string] $unreachable = 'PowerShell Direct unavailable or login failed.'
            Write-Output -InputObject "$($machine.Name): $unreachable"
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

function New-LabMachine {
    <#
    .SYNOPSIS
    Creates or starts one lab VM over its Os's base image: a prepared Windows
    VHDX as it is, AlmaLinux's GenericCloud image converted once.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [string] $image = $Lab.Images[$Machine.Os].Path
    if ($Machine.Family -eq 'Linux') {
        [hashtable] $base = @{ Lab = $Lab; Os = $Machine.Os; Create = $true; Confirm = $false }
        $image = Get-LabLinuxBaseImage @base
    }
    Set-LabVirtualMachine -Lab $Lab -Machine $Machine -BaseImage $image -Confirm:$false
}

function Read-LabCredential {
    <#
    .SYNOPSIS
    The DPAPI bundle Initialize-LabCredential.ps1 wrote, readable only by the
    host user who wrote it, with the shapes each fleet takes.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab
    )

    [hashtable] $bundle = Import-Clixml -LiteralPath $Lab.CredentialPath
    # Wrap secure strings as PSCredentials for remoting serialization.
    [hashtable] $windows = @{
        LocalAdministrator = $bundle.LocalAdministrator
        DomainAdministrator = [pscredential]::new("$($Lab.NetbiosName)\Administrator",
            $bundle.LocalAdministrator.Password)
        DsrmPassword = [pscredential]::new('dsrm', $bundle.DsrmPassword)
    }
    # The Linux guests take theirs in clear over SSH, for one DSC run.
    [hashtable] $linux = @{
        StoragePassword = [pscredential]::new('xmip_storage',
            $bundle.StoragePassword).GetNetworkCredential().Password
        ReplicationPassword = [pscredential]::new('xmip_replication',
            $bundle.ReplicationPassword).GetNetworkCredential().Password
    }
    return @{ Windows = $windows; Linux = $linux }
}

try {
    [hashtable] $inputState = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable
    [hashtable] $lab = Read-LabConfiguration -Path $inputState.ConfigPath
    if (-not $IsWindows) {
        throw 'Hyper-V provisioning requires a Windows host; configuration validation is portable.'
    }
    [bool] $mutate = $Operation -eq 'Set' -and
        $PSCmdlet.ShouldProcess($lab.LabId, "Configure the lab's $Scope")
    [string] $scopeName = $Scope
    if ($null -eq (Get-Command -Name Get-VM -ErrorAction SilentlyContinue)) {
        $scopeName = 'NoHyperV'
    }
    [string[]] $findings = switch ($scopeName) {
        'NoHyperV' {
            @('Hyper-V is not enabled; enable the host feature and reboot first.')
        }
        'Host' {
            if ($mutate) {
                Assert-LabMedia -Lab $lab
                Set-LabNetwork -Lab $lab -Confirm:$false
                foreach ($machine in @($lab.Machines | Where-Object Family -eq 'Windows')) {
                    New-LabMachine -Lab $lab -Machine $machine
                }
            }
            @(Get-LabHostFinding -Lab $lab)
        }
        'WindowsGuests' {
            [hashtable] $credential = (Read-LabCredential -Lab $lab).Windows
            @(Get-LabFleetFinding -Lab $lab -Credential $credential -Configure:$mutate)
        }
        'LinuxGuests' {
            [hashtable] $secret = @{}
            if ($mutate) {
                Assert-LabLinuxMedia -Lab $lab
                $secret = (Read-LabCredential -Lab $lab).Linux
            }
            foreach ($machine in @($lab.Machines | Where-Object Family -eq 'Linux')) {
                if ($mutate) {
                    New-LabMachine -Lab $lab -Machine $machine
                }
                Get-LabVirtualMachineFinding -Lab $lab -Machine $machine
            }
            @(Get-LabLinuxFleetFinding -Lab $lab -Secret $secret -Configure:$mutate)
        }
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
