#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The node's service on its machine (node.resource.ps1): whether it runs
    and starts with the machine, started and stopped, and a node this deploy
    restarted waited for until it is ready, as xmip-service --readiness says,
    before the next node is deployed (ADR-0056, amendment 2026-11-23).
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

function Wait-NodeReadiness {
    <#
    .SYNOPSIS
    Wait until the node this deploy restarted is ready, before the next node
    is deployed, as xmip-service --readiness says in the node's own words:
    it runs its slice and its Xmip Storage stands Fine, a Storage node the
    primary or a standby ready and following, asked again as the node
    publishes, never a sleep (the owner, 2026-11-23: "That has to be
    sorted, nothing can be left"; ADR-0056, amendment 2026-11-23). A
    Storage node restarted comes back a standby, and its primary stopped in
    order before it follows ready has no standby to hand over to. Refused
    past -Instance.ready seconds.
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
