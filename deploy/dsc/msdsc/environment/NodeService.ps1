#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The node's service on its machine (node.resource.ps1): whether it runs
    and starts with the machine, started and stopped, and restarted once and
    waited for once, after the last step that changes what it runs: the
    steps before it leave what they changed in deploy.pending beside the
    node's configuration, `restart` where a file the node reads changed and
    `ready` where its package's install restarted it, and the Service step
    restarts a node that asks it and waits until it is ready, as
    xmip-service --readiness says, before the next node is deployed
    (ADR-0056, amendments 2026-11-23 and 2026-11-24). Until 2026-11-24 the
    Slice step restarted a node and asked it, before its certificates and
    its package were placed, on the program installed then.
    Dot-sourced by node.resource.ps1 and by test/MsdscEnvironment.Test.ps1.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Test-NodeServiceActive {
    <#
    .SYNOPSIS
    Whether the node's service runs now: its Windows service running, its
    systemd unit active; false where it is not registered.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($IsWindows) {
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        return $null -ne $service -and $service.Status -eq 'Running'
    }
    & systemctl is-active --quiet $Name
    return $LASTEXITCODE -eq 0
}

$script:NodePendingFile = 'deploy.pending'

function Get-NodePending {
    <#
    .SYNOPSIS
    What this deploy left for the node's Service step in its configuration
    folder: `restart` where a file the node reads changed while it ran,
    `ready` where its package's install restarted it; nothing where neither.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Configuration
    )

    [string] $path = Join-Path -Path $Configuration -ChildPath $script:NodePendingFile
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return ''
    }
    return (Get-Content -LiteralPath $path -Raw).Trim()
}

function Set-NodePending {
    <#
    .SYNOPSIS
    Leave the node's Service step what changed: `restart`, a file the node
    reads, which a restart after it takes; `ready`, a restart that took
    every file placed before it, so the node is waited for and not restarted
    again. Only a node that runs is left either: one that does not is
    started by the package or the Service step, by what is placed.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Configuration,

        [Parameter(Mandatory = $true)]
        [ValidateSet('restart', 'ready')]
        [string] $Pending
    )

    [string] $path = Join-Path -Path $Configuration -ChildPath $script:NodePendingFile
    if ($PSCmdlet.ShouldProcess($path, "Leave the node's Service step '$Pending'")) {
        $null = New-Item -ItemType Directory -Force -Path $Configuration
        Set-Content -LiteralPath $path -Value $Pending
    }
}

function Set-NodeService {
    <#
    .SYNOPSIS
    The node's service running and started with the machine, after every
    step that changes what it runs: restarted once where a file it reads
    changed since it started, started where it does not run, and, where it
    ran before this deploy and was restarted by it, waited for once until it
    is ready (Wait-NodeReadiness). One that did not run is started waiting
    for nothing, its environment's nodes started together after
    (Xmip.Environment/Started).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if (-not $PSCmdlet.ShouldProcess($Instance.name, 'Run, restarting it where it asks')) {
        return
    }

    [string] $pending = if ($Instance['configuration']) {
        Get-NodePending -Configuration $Instance.configuration
    }
    else {
        ''
    }
    [bool] $ran = Test-NodeServiceActive -Name $Instance.name
    if ($ran -and $pending -eq 'restart') {
        Restart-NodeService -Name $Instance.name
    }
    Start-NodeService -Name $Instance.name -Confirm:$false
    if ($ran -and $pending) {
        Wait-NodeReadiness -Instance $Instance
    }
    if ($pending) {
        Remove-Item -LiteralPath (
            Join-Path -Path $Instance.configuration -ChildPath $script:NodePendingFile)
    }
}

function Restart-NodeService {
    <#
    .SYNOPSIS
    Restart the node's service, which runs: its Windows service, its
    systemd unit.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($IsWindows) {
        Restart-Service -Name $Name
        return
    }
    Invoke-DscProgram -Program 'systemctl' -Argument @('restart', $Name) | Out-Null
}

function Wait-NodeReadiness {
    <#
    .SYNOPSIS
    Wait until the node this deploy restarted is ready, before the next node
    is deployed, as xmip-service --readiness says in the node's own words:
    it runs its slice and its Xmip Storage stands Fine, a Storage node the
    primary or a standby ready and following, told as the node publishes,
    never a sleep (the owner, 2026-11-23: "That has to be sorted, nothing
    can be left"; ADR-0056, amendments 2026-11-23 and 2026-11-24). A
    Storage node restarted comes back a standby, and its primary stopped in
    order before it follows ready has no standby to hand over to. Asked once,
    by the Service step, of the program the package installed. Refused past
    -Instance.ready seconds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $placed = Join-Path -Path $Instance.configuration -ChildPath 'node.xmip'
    [string] $within = [string] [int] $Instance['ready']
    [string[]] $argument = @('--configuration', $placed, '--readiness', '--within', $within)
    try {
        Invoke-DscProgram -Program $Instance.program -Argument $argument | Out-Null
    }
    catch {
        throw ("REFUSED: node $($Instance.node) is not ready within $within s, so no next " +
            "node is deployed: $($_.Exception.Message)")
    }
}
function Test-NodeServiceRunning {
    <#
    .SYNOPSIS
    Whether the node's service runs and starts with the machine: its
    Windows service running and automatic, its systemd unit active and
    enabled.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if (-not (Test-NodeServiceActive -Name $Name)) {
        return $false
    }
    if ($IsWindows) {
        return (Get-Service -Name $Name).StartType -eq 'Automatic'
    }
    & systemctl is-enabled --quiet $Name
    return $LASTEXITCODE -eq 0
}

function Start-NodeService {
    <#
    .SYNOPSIS
    Make the node's service start with the machine and start it, waiting
    for nothing: a node of a cluster whose Storage nodes are not all up yet
    refuses to accept work, so the environment's nodes are started together
    after (Xmip.Environment/Started), and test says whether this one runs.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Enable and start')) {
        return
    }

    if ($IsWindows) {
        Set-Service -Name $Name -StartupType Automatic
        Start-Service -Name $Name -ErrorAction SilentlyContinue
        return
    }

    Invoke-DscProgram -Program 'systemctl' -Argument @('enable', $Name) | Out-Null
    Invoke-DscProgram -Program 'systemctl' -Argument @('start', '--no-block', $Name) | Out-Null
}

function Stop-NodeService {
    <#
    .SYNOPSIS
    Stop the node's service where it runs, so what it holds open, its
    module libraries, can be replaced; nothing where it is not registered
    or not running. The install that follows starts it again.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Stop')) {
        return
    }

    if ($IsWindows) {
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $service -and $service.Status -ne 'Stopped') {
            Stop-Service -Name $Name -Force
        }
        return
    }

    if (Test-NodeServiceActive -Name $Name) {
        Invoke-DscProgram -Program 'systemctl' -Argument @('stop', $Name) | Out-Null
    }
}
