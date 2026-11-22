#requires -PSEdition Core
#requires -Version 7.7.0

<#
    A program placed on a machine and registered as its service by its own
    --install (node.resource.ps1, kind Program): the Essentials' far end on
    a machine of its own, xmip-essentials-external, whose --install
    registers it through the runtime's one registration of a service and
    starts it, as xmip-service --install registers a node's. In its desired
    state where the program in place has its staged source's bytes and its
    service, xmip-<node>, is registered. Dot-sourced by node.resource.ps1
    and test/MsdscEnvironment.Test.ps1.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Get-NodeProgramState {
    <#
    .SYNOPSIS
    The program's state: whether it is in place with its source's bytes,
    whether its service is registered, and _exist, both.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $state = $Instance.Clone()
    [bool] $placed = (Test-Path -LiteralPath $Instance.path -PathType Leaf) -and
        (Test-Path -LiteralPath $Instance.source -PathType Leaf) -and
        (Get-FileHash -LiteralPath $Instance.path -Algorithm SHA256).Hash -eq
        (Get-FileHash -LiteralPath $Instance.source -Algorithm SHA256).Hash
    $state.placed = $placed
    $state.registered = Test-NodeServiceRegistered -Name "xmip-$($Instance.node)"
    $state._exist = $placed -and $state.registered
    return $state
}

function Test-NodeServiceRegistered {
    <#
    .SYNOPSIS
    Whether a service of the name is registered: a Windows service, or a
    systemd unit's file.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($IsWindows) {
        return $null -ne (Get-Service -Name $Name -ErrorAction SilentlyContinue)
    }
    return Test-Path -LiteralPath "/etc/systemd/system/$Name.service" -PathType Leaf
}

function Install-NodeProgram {
    <#
    .SYNOPSIS
    The program placed from its staged source, its service stopped first
    where it runs so the file is free, and registered and started by its
    own --install with the instance's arguments.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if (-not $PSCmdlet.ShouldProcess($Instance.path, 'Place and register')) {
        return
    }
    [string] $name = "xmip-$($Instance.node)"
    if (Test-NodeServiceRegistered -Name $name) {
        Stop-NodeService -Name $name -Confirm:$false
    }
    New-Item -ItemType Directory -Path (Split-Path -Path $Instance.path -Parent) -Force |
        Out-Null
    Copy-Item -LiteralPath $Instance.source -Destination $Instance.path -Force
    if (-not $IsWindows) {
        Invoke-DscProgram -Program 'chmod' -Argument @('0755', $Instance.path) | Out-Null
    }
    Invoke-DscProgram -Program $Instance.path -Argument @($Instance.arguments) | Out-Null
}
