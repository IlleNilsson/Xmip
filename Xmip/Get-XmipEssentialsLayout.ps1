#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipEssentialsLayout {
    <#
        .SYNOPSIS
            Where the Essentials' binaries, the web host and this machine's
            run output live. One answer for every essentials cmdlet.

        .DESCRIPTION
            The roll, cluster and node binaries are cargo's debug build under
            test/core/essentials; the web host is the GUI's debug build. Everything
            a run writes on this machine — snapshots, run records, node logs —
            goes under .local-work/essentials, the device-local folder the
            estate reserves for running Xmip here (CONTRIBUTING.md:
            .local-work is where). Nothing here is created; Start-* create
            what they use.

            Image is where a run's per-instance images go, one directory per
            cluster: a process name is its image file's name, so a name that
            says which cluster and which node is a file per instance (ADR-0053,
            amendment 2026-09-20). They are hard links to the built binaries,
            never copies of the repository, and they are device-local like
            everything else a run writes here.

            Authority is the Essentials' own certificate authority, one for
            every roll in the area: the web host is served https under it, a
            tester's operator certificate is signed by it
            (Initialize-XmipEssentialsAuthority; ADR-0009, amendment
            2026-10-21), and the nodes a run starts as xmip-service are issued
            under it, so it outlives every run (ADR-0028, amendment
            2026-10-27).

            Configuration is the Essentials' own cluster cluster.xmip, the one
            file a run is the same over whether its nodes are simulated or on
            machines of their own (ADR-0028, amendment 2026-10-21): the nodes
            a run spawns where -Nodes names none, and what the environment
            templates under deploy/dsc put on each node machine.

            Estate is where a run of the estate's Pester suite writes its
            record and its log: .local-work/estate, beside the Essentials'
            area and not inside it, since it is no roll's.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    [string] $root = Get-XmipRepositoryRoot
    [string] $essentials = Join-Path -Path $root -ChildPath 'test/core/essentials'

    # Where cargo builds is cargo's own answer, not an assumption:
    # CARGO_TARGET_DIR moves it, and this follows, so the cmdlets link and run
    # what was just built rather than what is beside the crate. CONTRIBUTING.md
    # reserves .local-work for device-local state, naming a target choice as
    # the first of them; a session whose ordinary target directory is held open
    # by another session's roll sets it there and builds without touching it.
    [string] $chosen = $env:CARGO_TARGET_DIR
    [string] $target = if ([string]::IsNullOrWhiteSpace($chosen)) {
        Join-Path -Path $essentials -ChildPath 'target/debug'
    }
    else {
        Join-Path -Path $chosen -ChildPath 'debug'
    }

    [string] $suffix = if ($IsWindows) { '.exe' } else { '' }
    [string] $web = 'module/core/operation/gui/src/Xmip.Gui.Web/bin/Debug/net11.0/xmip-gui-web'

    return [PSCustomObject]@{
        Root       = $root
        Essentials = $essentials
        Configuration = Join-Path -Path $essentials -ChildPath 'configuration/cluster.xmip'
        Roll       = Join-Path -Path $target -ChildPath "xmip-essentials-roll$suffix"
        Cluster    = Join-Path -Path $target -ChildPath "xmip-essentials-cluster$suffix"
        Node       = Join-Path -Path $target -ChildPath "xmip-essentials-node$suffix"
        Web        = Join-Path -Path $root -ChildPath "$web$suffix"
        Area       = Join-Path -Path $root -ChildPath '.local-work/essentials'
        Authority  = Join-Path -Path $root -ChildPath '.local-work/essentials/authority'
        Image      = Join-Path -Path $root -ChildPath '.local-work/essentials/image'
        Estate     = Join-Path -Path $root -ChildPath '.local-work/estate'
        Suffix     = $suffix
    }
}

function Invoke-XmipEssentialsBuild {
    <#
        .SYNOPSIS
            Builds one Essentials binary, cargo's lines on the Verbose stream.
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

    $layout = Get-XmipEssentialsLayout
    [string] $path = switch ($Binary) {
        'roll' { $layout.Roll }
        'cluster' { $layout.Cluster }
        default { $layout.Node }
    }

    Write-Verbose "cargo build --bin $Binary in $($layout.Essentials)"
    Push-Location -LiteralPath $layout.Essentials

    try {
        [string[]] $bins = @('--bin', 'xmip-essentials-node')

        if ($Binary -in 'roll', 'cluster') {
            $bins += @('--bin', 'xmip-essentials-cluster')
        }

        if ($Binary -eq 'roll') {
            $bins += @('--bin', 'xmip-essentials-roll')
        }

        # The estate as it is on disk, every estate crate patched to its
        # working tree as a landing verifies (New-XmipLocalPatch), so a run
        # tests what is here and never only what was pushed.
        [string] $patch = New-XmipLocalPatch -RepositoryRoot $layout.Root

        # Cargo's first error is kept, so a failed build says why in its own
        # words and not only its exit code (Get-XmipTestStatus shows it).
        [string[]] $building = @('build', '--config', $patch) + $bins
        [pscustomobject] $built = Invoke-XmipTool -Tool cargo -Argument $building -Output Keep
        $built.Said | ForEach-Object { Write-Verbose $_ }
        [string] $first = @($built.Said | Where-Object { $_ -match '^error' } |
            Select-Object -First 1) -join ''
    }
    finally {
        Pop-Location
    }

    if (-not $built.Passed) {
        [string] $why = if ($first -ne '') { ": $first" } else { '.' }
        throw "cargo build --bin $Binary failed in $($layout.Essentials)$why"
    }

    return $path
}

function Invoke-XmipEssentialsService {
    <#
        .SYNOPSIS
            Builds the xmip-service a run of `Cluster` starts its nodes as, and
            says where it is.

        .DESCRIPTION
            Built as the personal-computer site builds it (Build-XmipService):
            every stage, Xmip Storage and the file transport, against the
            estate as it is on disk (New-XmipLocalPatch), in a build
            directory of its own, .local-work/essentials/service/target. The
            binary is copied
            to .local-work/essentials/service/<cluster>, so a later build never
            changes what a running roll's nodes run (ADR-0028, amendment
            2026-10-22).

        .PARAMETER Cluster
            The run's cluster.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster
    )

    $layout = Get-XmipEssentialsLayout
    [string] $patch = New-XmipLocalPatch -RepositoryRoot $layout.Root

    # A build directory of its own: one shared with the Essentials' own
    # build, a workspace whose lock pins other revisions, left rustc finding
    # two builds of one estate crate and refusing the service (2026-10-22).
    [string] $target = Join-Path -Path $layout.Area -ChildPath 'service/target'
    [string] $previous = $env:CARGO_TARGET_DIR
    $env:CARGO_TARGET_DIR = $target

    try {
        $null = Build-XmipService -Site personal-computer -CargoArgument @('--config', $patch)
    }
    finally {
        $env:CARGO_TARGET_DIR = $previous
    }

    [string] $built = Join-Path -Path $target -ChildPath "debug/xmip-service$($layout.Suffix)"
    [string] $folder = Join-Path -Path $layout.Area -ChildPath "service/$Cluster"
    $null = New-Item -ItemType Directory -Path $folder -Force
    [string] $kept = Join-Path -Path $folder -ChildPath "xmip-service$($layout.Suffix)"
    Copy-Item -LiteralPath $built -Destination $kept -Force

    return $kept
}


function Get-XmipEssentialsPublication {
    <#
        .SYNOPSIS
            Where the roll of a cluster publishes its snapshot, history and
            activity in an area, as the roll itself says.

        .DESCRIPTION
            The names are the Essentials' to decide (environment.rs,
            publish_paths), so this asks the roll binary —
            `xmip-essentials-roll --publication <cluster> <area>`, which
            prints them and starts nothing — rather than naming the files a
            second time. Refused in words when the roll cannot answer.

        .PARAMETER Roll
            The roll binary, from Invoke-XmipEssentialsBuild.

        .PARAMETER Cluster
            The cluster the roll rolls as.

        .PARAMETER Path
            The area the roll publishes in, as XMIP_ESSENTIALS_AREA tells it.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $Roll,

        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter(Mandatory)]
        [string] $Path
    )

    # The exit code is read here, so the refusal names the roll and what it
    # said (ADR-0055). Assigned in this scope alone.
    $PSNativeCommandUseErrorActionPreference = $false
    [string[]] $said = @(& $Roll '--publication' $Cluster $Path 2>&1 | ForEach-Object { "$_" })

    if ($LASTEXITCODE -ne 0) {
        throw ("REFUSED: $Roll could not say where cluster $Cluster publishes " +
            "(exit $LASTEXITCODE): $($said -join ' ')")
    }

    [hashtable] $where = @{}

    foreach ($line in $said) {
        [string[]] $pair = $line.Split('=', 2)

        if ($pair.Count -eq 2) {
            $where[$pair[0].Trim()] = $pair[1].Trim()
        }
    }

    return [PSCustomObject] @{
        Snapshot = [string] $where['snapshot']
        History  = [string] $where['history']
        Activity = [string] $where['activity']
    }
}
