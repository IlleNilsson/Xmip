#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The Domain kind of environment.resource.ps1, on the machine DSC runs on:
    the environment's Active Directory domain. Its controller, a Windows
    machine of the environment and the network's DNS server, is made the
    first domain controller of a new forest of the environment's domain, its
    DNS server answering the domain's zone; every other Windows machine is
    joined to it (the owner, 2026-11-21: "The VMs need a domain"). AlmaLinux
    machines are not joined; they find the nodes by the names their hosts
    file keeps (NodePackage.ps1).

    The machine is reached as Xmip.Environment/Machine reaches it
    (New-EnvironmentSession), and the Administrator's secret goes there
    inside the session alone, never in a file: the forest's Directory
    Services Restore Mode password is the Administrator's, and the
    Administrator of a new forest is the controller's own, so a machine
    joins as Administrator@<domain> with the same secret.

    Promoting and joining each restart the machine. Set starts the restart
    and returns; a machine that does not answer is not yet in its desired
    state, never an error, so Deploy-XmipEnvironment sets the step again
    until it is (Get-XmipDeployStep marks it Install).

    Dot-sourced by environment.resource.ps1 and by
    test/MsdscEnvironment.Test.ps1.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Open-EnvironmentDomainSession {
    <#
    .SYNOPSIS
    A session on the machine, or nothing where it does not answer yet, as
    while it restarts.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.PSSession])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    try {
        return New-EnvironmentSession -Instance $Instance -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-EnvironmentDomain {
    <#
    .SYNOPSIS
    The machine's state: _exist where the controller is a domain controller
    of the domain whose DNS server holds the domain's zone, or where a
    member is joined to the domain; false where it does not answer.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $state = $Instance.Clone()
    $state._exist = $false
    $session = Open-EnvironmentDomainSession -Instance $Instance
    if ($null -eq $session) {
        $state.answering = $false
        return $state
    }
    try {
        $state.answering = $true
        [object[]] $argument = @($Instance.domain, [bool] $Instance.controller)
        # A session that breaks as the machine restarts is a machine not
        # answering yet, never an error.
        [hashtable] $asked = @{ Session = $session; ArgumentList = $argument; ErrorAction = 'Stop' }
        $state._exist = [bool] (Invoke-EnvironmentCommand @asked -ScriptBlock {
                param($Domain, $Controller)
                $system = Get-CimInstance -ClassName Win32_ComputerSystem
                if (-not $Controller) {
                    return $system.PartOfDomain -and $system.Domain -eq $Domain
                }
                # 4 and 5: a backup and the primary domain controller. The
                # zone is asked too: the names step writes into it, and a
                # zone not yet loaded would be made again as a file's.
                $zone = Get-Command -Name Get-DnsServerZone -ErrorAction SilentlyContinue
                return $system.DomainRole -ge 4 -and $null -ne $zone -and
                $null -ne (Get-DnsServerZone -Name $Domain -ErrorAction SilentlyContinue)
            })
    }
    catch {
        $state.answering = $false
        $state._exist = $false
    }
    finally {
        Remove-PSSession -Session $session
    }
    return $state
}

function Set-EnvironmentDomain {
    <#
    .SYNOPSIS
    Promote the controller, or join a member, where it is not so yet, and
    restart it; nothing where the machine does not answer, or is already
    as asked.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if ((Get-EnvironmentDomain -Instance $Instance)._exist) {
        return
    }
    [string] $act = if ($Instance.controller) { "Make the forest $($Instance.domain)" }
    else { "Join $($Instance.domain)" }
    if (-not $PSCmdlet.ShouldProcess($Instance.name, $act)) {
        return
    }
    $session = Open-EnvironmentDomainSession -Instance $Instance
    if ($null -eq $session) {
        return
    }
    [pscredential] $administrator = Read-MachineSecret -Path $Instance.secretPath
    [object[]] $argument = @($Instance.domain, [bool] $Instance.controller, $administrator)
    try {
        # What the promotion and the join warn of reaches standard error
        # (Invoke-EnvironmentCommand), standard output kept the JSON.
        Invoke-EnvironmentCommand -Session $session -ArgumentList $argument -ScriptBlock {
            param($Domain, $Controller, $Administrator)
            $ErrorActionPreference = 'Stop'
            $ProgressPreference = 'SilentlyContinue'
            $system = Get-CimInstance -ClassName Win32_ComputerSystem
            # A controller already promoted, its zone not loaded yet, is left
            # to finish starting: only a change is followed by a restart.
            if ($Controller -and $system.DomainRole -lt 4) {
                Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools |
                    Out-Null
                [hashtable] $forest = @{
                    DomainName = $Domain
                    InstallDns = $true
                    SafeModeAdministratorPassword = $Administrator.Password
                    NoRebootOnCompletion = $true
                    Force = $true
                }
                Install-ADDSForest @forest | Out-Null
            }
            elseif (-not $Controller -and -not ($system.PartOfDomain -and $system.Domain -eq $Domain)) {
                [pscredential] $joining = [pscredential]::new(
                    "Administrator@$Domain", $Administrator.Password)
                Add-Computer -DomainName $Domain -Credential $joining -Force
            }
            else {
                return
            }
            # Restarted a moment after the session returns, which a restart
            # inside it would break.
            & shutdown.exe /r /t 5 /d p:4:1 /c 'Xmip: the environment''s domain' | Out-Null
        }
    }
    finally {
        Remove-PSSession -Session $session
    }
}
