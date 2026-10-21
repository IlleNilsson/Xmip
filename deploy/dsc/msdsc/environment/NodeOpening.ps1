#requires -Version 7.6

<#
    The firewall openings of a node machine (node.resource.ps1, kind
    Opening): exactly the ports xmip-service --listening says the node's
    configuration listens on.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Get-NodeListening {
    <#
    .SYNOPSIS
    The ports the node's configuration listens on, as xmip-service
    --listening says them: 7401/tcp, one each.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string[]] $argument = @('--configuration', $Instance.configuration, '--listening')

    return @(Invoke-NodeProgram -Program $Instance.program -Argument $argument |
            Where-Object { $_ -match '^\d+/(tcp|udp)\b' } |
            ForEach-Object { ($_ -split '\s+')[0] } | Sort-Object -Unique)
}

function Get-NodeOpened {
    <#
    .SYNOPSIS
    The ports opened for the node: the inbound rules named xmip-<node>-* on
    Windows, the ports of firewalld's service xmip-<node> on Linux.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Node
    )

    if ($IsWindows) {
        return @(Get-NetFirewallRule -Name "xmip-$Node-*" -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Name.Substring("xmip-$Node-".Length) -replace '-', '/' } |
                Sort-Object -Unique)
    }

    [string[]] $services = @(Invoke-NodeProgram -Program 'firewall-cmd' -Argument @(
            '--permanent', '--get-services'))

    if (("$services" -split '\s+') -notcontains "xmip-$Node") {
        return @()
    }

    [string[]] $ports = @(Invoke-NodeProgram -Program 'firewall-cmd' -Argument @(
            '--permanent', "--service=xmip-$Node", '--get-ports'))

    return @(("$ports" -split '\s+') | Where-Object { $_ } | Sort-Object -Unique)
}

function Set-NodeOpened {
    <#
    .SYNOPSIS
    Open exactly the ports the configuration listens on, and close every
    other opening the node had.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $node = $Instance.node
    [string[]] $wanted = @(Get-NodeListening -Instance $Instance)

    if (-not $PSCmdlet.ShouldProcess("xmip-$node", "Open $($wanted -join ', ')")) {
        return
    }

    if ($IsWindows) {
        Get-NetFirewallRule -Name "xmip-$node-*" -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule

        foreach ($port in $wanted) {
            [string] $number, [string] $protocol = $port -split '/'
            [hashtable] $rule = @{
                Name        = "xmip-$node-$number-$protocol"
                DisplayName = "Xmip node $node, $port"
                Direction   = 'Inbound'
                Action      = 'Allow'
                Protocol    = $protocol.ToUpperInvariant()
                LocalPort   = $number
            }
            New-NetFirewallRule @rule | Out-Null
        }

        return
    }

    [string] $service = "xmip-$node"

    [string[]] $services = @(Invoke-NodeProgram -Program 'firewall-cmd' -Argument @(
            '--permanent', '--get-services'))

    if (("$services" -split '\s+') -notcontains $service) {
        Invoke-NodeProgram -Program 'firewall-cmd' -Argument @(
            '--permanent', "--new-service=$service") | Out-Null
    }

    foreach ($port in @(Get-NodeOpened -Node $node)) {
        Invoke-NodeProgram -Program 'firewall-cmd' -Argument @(
            '--permanent', "--service=$service", "--remove-port=$port") | Out-Null
    }

    foreach ($port in $wanted) {
        Invoke-NodeProgram -Program 'firewall-cmd' -Argument @(
            '--permanent', "--service=$service", "--add-port=$port") | Out-Null
    }

    Invoke-NodeProgram -Program 'firewall-cmd' -Argument @(
        '--permanent', "--add-service=$service") | Out-Null
    Invoke-NodeProgram -Program 'firewall-cmd' -Argument @('--reload') | Out-Null
}

