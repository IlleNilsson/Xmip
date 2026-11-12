#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The Started kind of environment.resource.ps1: every node of the
    environment running, started together. A node refuses to accept work
    until the cluster's Xmip Storage answers, and a Storage node until every
    Storage node its cluster lists answers (ADR-0056, amendment 2026-11-08),
    so no node of them starts alone, one machine after another: set starts
    every node that does not run, and again, every five seconds, each one
    that stopped, until every one runs or the window is spent. Each machine
    is reached as Xmip.Environment/Machine reaches it (EnvironmentSsh.ps1,
    EnvironmentMachine.ps1). Dot-sourced by environment.resource.ps1 and by
    test/MsdscEnvironment.Test.ps1.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Get-EnvironmentNodeReach {
    <#
    .SYNOPSIS
    How one node's machine is reached: the instance's login, key,
    known_hosts and secret, with the machine's name, address and family.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Node
    )

    return @{
        name = $Node.machine.name
        address = $Node.machine.address
        family = $Node.machine.family
        login = $Instance.login
        keyPath = $Instance.keyPath
        knownHosts = $Instance.knownHosts
        secretPath = $Instance.secretPath
    }
}

function Get-EnvironmentNodeService {
    <#
    .SYNOPSIS
    How a node's service stands on its machine: active, activating, failed
    or inactive, as systemd says it, Running and the rest as Windows does;
    unreachable where the machine does not answer.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Reach,

        [Parameter(Mandatory = $true)]
        [string] $Node
    )

    [int] $port = if ($Reach.family -eq 'Windows') { 5985 } else { 22 }
    [hashtable] $answer = @{ TargetName = $Reach.address; TcpPort = $port; TimeoutSeconds = 1 }
    if (-not (Test-Connection @answer -Quiet)) {
        return 'unreachable'
    }
    if ($Reach.family -eq 'Windows') {
        $session = New-EnvironmentSession -Instance $Reach
        try {
            return "$(Invoke-Command -Session $session -ArgumentList "xmip-$Node" -ScriptBlock {
                    param($Name)
                    (Get-Service -Name $Name -ErrorAction SilentlyContinue).Status
                })"
        }
        finally {
            Remove-PSSession -Session $session
        }
    }
    [string] $unit = ConvertTo-EnvironmentShellWord -Value "xmip-$Node"
    return (@(Invoke-EnvironmentSsh -Instance $Reach -Command (
                "systemctl is-active $unit || true")) -join '').Trim()
}

function Start-EnvironmentNodeService {
    <#
    .SYNOPSIS
    Start a node's service once more, waiting for nothing: its failure
    forgotten first, so systemd starts it again.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Reach,

        [Parameter(Mandatory = $true)]
        [string] $Node
    )

    if (-not $PSCmdlet.ShouldProcess("xmip-$Node", 'Start')) {
        return
    }
    if ($Reach.family -eq 'Windows') {
        $session = New-EnvironmentSession -Instance $Reach
        try {
            Invoke-Command -Session $session -ArgumentList "xmip-$Node" -ScriptBlock {
                param($Name)
                Start-Service -Name $Name -ErrorAction SilentlyContinue
            }
        }
        finally {
            Remove-PSSession -Session $session
        }
        return
    }
    [string] $unit = ConvertTo-EnvironmentShellWord -Value "xmip-$Node"
    Invoke-EnvironmentSsh -Instance $Reach -Command (
        "sudo systemctl reset-failed $unit; sudo systemctl start --no-block $unit") | Out-Null
}

function Get-EnvironmentStarted {
    <#
    .SYNOPSIS
    The state: each node's service as it stands, and _exist where every one
    runs.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $state = $Instance.Clone()
    [hashtable] $stands = @{}
    foreach ($node in @($Instance.nodes)) {
        [hashtable] $reach = Get-EnvironmentNodeReach -Instance $Instance -Node $node
        $stands[$node.node] = Get-EnvironmentNodeService -Reach $reach -Node $node.node
    }
    $state.services = $stands
    $state._exist = @($stands.Values | Where-Object { $_ -notin 'active', 'Running' }).Count -eq 0
    return $state
}

function Set-EnvironmentStarted {
    <#
    .SYNOPSIS
    Start every node that does not run, together, and again every five
    seconds each one that stopped, until every one runs or the instance's
    window, in seconds, is spent; then answer the state.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [datetime] $until = [datetime]::UtcNow.AddSeconds([int] $Instance.window)
    do {
        [hashtable] $state = Get-EnvironmentStarted -Instance $Instance
        if ($state._exist -or -not $PSCmdlet.ShouldProcess('the nodes', 'Start together')) {
            return $state
        }
        foreach ($node in @($Instance.nodes)) {
            [string[]] $leave = @('active', 'activating', 'Running', 'unreachable')
            if ($state.services[$node.node] -notin $leave) {
                [hashtable] $reach = Get-EnvironmentNodeReach -Instance $Instance -Node $node
                Start-EnvironmentNodeService -Reach $reach -Node $node.node -Confirm:$false
            }
        }
        Start-Sleep -Seconds 5
    } while ([datetime]::UtcNow -lt $until)
    return Get-EnvironmentStarted -Instance $Instance
}
