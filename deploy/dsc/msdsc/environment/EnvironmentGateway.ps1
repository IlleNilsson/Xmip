#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The Gateway kind of environment.resource.ps1, on the machine DSC runs on:
    the network's way out through its gateway machine, a Windows machine of
    the environment, the domain's controller in the examples (the owner,
    2026-11-24: "the VM DSC can be a gateway to internet for those machines
    that needs it", "A good choice would be the DC", "The DC would be behind
    my firewall"). What the machine is given is
    deploy/dsc/machine/WindowsGateway.ps1's, the one script both technologies
    run: here it is sent whole into the machine's session, the machine
    reached as Xmip.Environment/Domain reaches it
    (Open-EnvironmentDomainSession); Ansible's xmip_gateway role hands it to
    win_powershell.

    A machine that does not answer is not yet in its desired state, never an
    error; a machine without its second adapter is refused, the adapter
    being its hypervisor's to give.

    Dot-sourced by environment.resource.ps1 and by
    test/DeployGateway.Test.ps1.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Invoke-EnvironmentGateway {
    <#
    .SYNOPSIS
    One of WindowsGateway.ps1's two acts run on the machine over its
    session, which Invoke-EnvironmentCommand takes: its findings, or its set.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Session,

        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Get-WindowsGatewayFinding', 'Set-WindowsGateway')]
        [string] $Act
    )

    [string] $file = Join-Path -Path $PSScriptRoot -ChildPath '../../machine/WindowsGateway.ps1'
    [string] $text = "param(`$Address, `$Prefix)`n" + (Get-Content -LiteralPath $file -Raw) +
    "`n$Act -Address `$Address -Prefix `$Prefix"
    [hashtable] $asked = @{
        Session = $Session
        ScriptBlock = [scriptblock]::Create($text)
        ArgumentList = @($Instance.address, $Instance.prefix)
    }
    Invoke-EnvironmentCommand @asked
}

function Get-EnvironmentGateway {
    <#
    .SYNOPSIS
    The machine's state: _exist where it is the network's gateway as
    WindowsGateway.ps1 reads it, and findings, how it differs; false where
    it does not answer.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $state = $Instance.Clone()
    $state._exist = $false
    $state.findings = @()
    $session = Open-EnvironmentDomainSession -Instance $Instance
    if ($null -eq $session) {
        $state.answering = $false
        $state.findings = @("$($Instance.name): does not answer.")
        return $state
    }
    try {
        $state.answering = $true
        [string[]] $found = @(Invoke-EnvironmentGateway -Session $session -Instance $Instance -Act (
                'Get-WindowsGatewayFinding') | ForEach-Object { [string] $_ })
        $state.findings = $found
        $state._exist = $found.Count -eq 0
    }
    finally {
        Remove-PSSession -Session $session
    }
    return $state
}

function Set-EnvironmentGateway {
    <#
    .SYNOPSIS
    Makes the machine the network's gateway where it is not yet; nothing
    where it does not answer, or already is.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if ((Get-EnvironmentGateway -Instance $Instance)._exist -or
        -not $PSCmdlet.ShouldProcess($Instance.name, 'Make the network''s way out')) {
        return
    }
    $session = Open-EnvironmentDomainSession -Instance $Instance
    if ($null -eq $session) {
        return
    }
    try {
        Invoke-EnvironmentGateway -Session $session -Instance $Instance -Act 'Set-WindowsGateway' |
            Out-Null
    }
    finally {
        Remove-PSSession -Session $session
    }
}
