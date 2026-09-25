#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipPlaygroundLayout {
    <#
        .SYNOPSIS
            Where the Playground's binaries, the web host and this machine's
            run output live. One answer for every playground cmdlet.

        .DESCRIPTION
            The roll, cluster and node binaries are cargo's debug build under
            test/core/playground; the web host is the GUI's debug build. Everything
            a run writes on this machine — snapshots, run records, node logs —
            goes under .local-work/playground, the device-local folder the
            estate reserves for running Xmip here (CONTRIBUTING.md:
            .local-work is where). Nothing here is created; Start-* create
            what they use.

            Image is where a run's per-instance images go, one directory per
            cluster: a process name is its image file's name, so a name that
            says which cluster and which node is a file per instance (ADR-0053,
            amendment 2026-09-20). They are hard links to the built binaries,
            never copies of the repository, and they are device-local like
            everything else a run writes here.

            Estate is where a run of the estate's Pester suite writes its
            record and its log: .local-work/estate, beside the Playground's
            area and not inside it, since it is no roll's.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    [string] $root = Get-XmipRepositoryRoot
    [string] $playground = Join-Path -Path $root -ChildPath 'test/core/playground'

    # Where cargo builds is cargo's own answer, not an assumption:
    # CARGO_TARGET_DIR moves it, and this follows, so the cmdlets link and run
    # what was just built rather than what is beside the crate. CONTRIBUTING.md
    # reserves .local-work for device-local state, naming a target choice as
    # the first of them; a session whose ordinary target directory is held open
    # by another session's roll sets it there and builds without touching it.
    [string] $chosen = $env:CARGO_TARGET_DIR
    [string] $target = if ([string]::IsNullOrWhiteSpace($chosen)) {
        Join-Path -Path $playground -ChildPath 'target/debug'
    }
    else {
        Join-Path -Path $chosen -ChildPath 'debug'
    }

    [string] $suffix = if ($IsWindows) { '.exe' } else { '' }
    [string] $web = 'module/core/operation/gui/src/Xmip.Gui.Web/bin/Debug/net11.0/xmip-gui-web'

    return [PSCustomObject]@{
        Root       = $root
        Playground = $playground
        Roll       = Join-Path -Path $target -ChildPath "xmip-playground-roll$suffix"
        Cluster    = Join-Path -Path $target -ChildPath "xmip-playground-cluster$suffix"
        Node       = Join-Path -Path $target -ChildPath "xmip-playground-node$suffix"
        Web        = Join-Path -Path $root -ChildPath "$web$suffix"
        Area       = Join-Path -Path $root -ChildPath '.local-work/playground'
        Image      = Join-Path -Path $root -ChildPath '.local-work/playground/image'
        Estate     = Join-Path -Path $root -ChildPath '.local-work/estate'
        Suffix     = $suffix
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
