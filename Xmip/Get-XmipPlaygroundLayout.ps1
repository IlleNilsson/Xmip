#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipPlaygroundLayout {
    <#
        .SYNOPSIS
            Where the Playground's binaries, the web host and this machine's
            run output live. One answer for every playground cmdlet.

        .DESCRIPTION
            The roll, cluster and node binaries are cargo's debug build under
            test/playground; the web host is the GUI's debug build. Everything
            a run writes on this machine — snapshots, run records, node logs —
            goes under .local-work/playground, the device-local folder the
            estate reserves for running Xmip here (CLAUDE.md: .local-work is
            where). Nothing here is created; Start-* create what they use.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    [string] $root = Get-XmipRepositoryRoot
    [string] $playground = Join-Path -Path $root -ChildPath 'test/playground'
    [string] $target = Join-Path -Path $playground -ChildPath 'target/debug'
    [string] $suffix = if ($IsWindows) { '.exe' } else { '' }
    [string] $web = 'module/operation/gui/src/Xmip.Gui.Web/bin/Debug/net11.0/xmip-gui-web'

    return [PSCustomObject]@{
        Root       = $root
        Playground = $playground
        Roll       = Join-Path -Path $target -ChildPath "xmip-playground-roll$suffix"
        Cluster    = Join-Path -Path $target -ChildPath "xmip-playground-cluster$suffix"
        Node       = Join-Path -Path $target -ChildPath "xmip-playground-node$suffix"
        Web        = Join-Path -Path $root -ChildPath "$web$suffix"
        Area       = Join-Path -Path $root -ChildPath '.local-work/playground'
    }
}

function Invoke-XmipPlaygroundBuild {
    <#
        .SYNOPSIS
            Builds one Playground binary, cargo's lines on the Verbose stream.
            Cargo is a no-op when the binary is current, so this always runs:
            a stale binary silently running yesterday's scenarios is the thing
            it prevents.

        .PARAMETER Binary
            `roll`, `cluster` or `node`. The roll spawns the cluster and the
            cluster spawns the nodes (the owner, 2026-09-19), so building the
            roll builds all three and building the cluster builds it and the
            node.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('roll', 'cluster', 'node')]
        [string] $Binary
    )

    $layout = Get-XmipPlaygroundLayout
    [string] $path = switch ($Binary) {
        'roll' { $layout.Roll }
        'cluster' { $layout.Cluster }
        default { $layout.Node }
    }

    Write-Verbose "cargo build --bin $Binary in $($layout.Playground)"
    Push-Location -LiteralPath $layout.Playground

    try {
        [string[]] $bins = @('--bin', 'xmip-playground-node')

        if ($Binary -in 'roll', 'cluster') {
            $bins += @('--bin', 'xmip-playground-cluster')
        }

        if ($Binary -eq 'roll') {
            $bins += @('--bin', 'xmip-playground-roll')
        }

        & cargo build @bins 2>&1 | ForEach-Object { Write-Verbose "$_" }
    }
    finally {
        Pop-Location
    }

    if ($LASTEXITCODE -ne 0) {
        throw "cargo build --bin $Binary exited $LASTEXITCODE in $($layout.Playground)."
    }

    return $path
}
