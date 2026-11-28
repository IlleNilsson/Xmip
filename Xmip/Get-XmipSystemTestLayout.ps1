#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipSystemTestLayout {
    <#
        .SYNOPSIS
            Where the System Tests' binaries, the web host and this machine's
            run output live. One answer for every System Tests cmdlet.

        .DESCRIPTION
            The roll, cluster and node binaries are cargo's `measured` build of
            test/core/system-test, in the estate's one workspace: the board and
            the demo read latency from them, and the millisecond rule is
            measured on the optimized build (ADR-0018, amendment 2026-11-20).
            They build in Target, .local-work/system-test/target, a build
            directory of their own, so a running roll never holds a file a
            landing builds.
            The web host is the GUI's debug build. Everything
            a run writes on this machine — snapshots, run records, node logs —
            goes under .local-work/system-test, the device-local folder the
            estate reserves for running Xmip here (CONTRIBUTING.md:
            .local-work is where). Nothing here is created; Start-* create
            what they use.

            Image is where a run's per-instance images go, one directory per
            cluster: a process name is its image file's name, so a name that
            says which cluster and which node is a file per instance (ADR-0053,
            amendment 2026-09-20). They are hard links to the built binaries,
            never copies of the repository, and they are device-local like
            everything else a run writes here.

            Authority is the System Tests' own certificate authority, one for
            every roll in the area: the web host is served https under it, a
            tester's operator certificate is signed by it
            (Initialize-XmipSystemTestAuthority; ADR-0009, amendment
            2026-10-21), and the nodes a run starts as xmip-service are issued
            under it, so it outlives every run (ADR-0028, amendment
            2026-10-27).

            Configuration is the Reference Environment,
            Xmip-reference-environment.xmip, the one
            file a run is the same over whether its nodes are simulated or on
            machines of their own (ADR-0028, amendment 2026-10-21): the nodes
            a run spawns where -Nodes names none, and what the environment
            templates under deploy/dsc put on each node machine.

            Estate is where a run of the estate's Pester suite writes its
            record and its log: .local-work/estate, beside the System Tests'
            area and not inside it, since it is no roll's. Demo is the same
            for a run of Core.Demo, the demo readiness check, which reads a
            roll through Desktop, the Desktop operations app's project, and
            builds Extension, the VS Code extension's crate (ADR-0028,
            amendment 2026-11-10).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    [pscustomobject] $estate = Get-XmipEstateLayout
    [string] $root = $estate.Root
    [string] $systemTest = Join-Path -Path $root -ChildPath 'test/core/system-test'

    # The roll, cluster and node build in a build directory of their own,
    # under the System Tests' area, in its `measured` folder: a running roll
    # holds its binaries open (its images are hard links to them), and on
    # Windows a landing's timing runs, which build in the estate's
    # (Get-XmipEstateLayout, Build), would fail on a file held there.
    [string] $built = Join-Path -Path $estate.SystemTest -ChildPath 'target'
    [string] $target = Join-Path -Path $built -ChildPath $script:XmipMeasuredProfile

    [string] $suffix = if ($IsWindows) { '.exe' } else { '' }
    [string] $web = 'module/core/operation/gui/src/Xmip.Gui.Web/bin/Debug/net11.0/xmip-gui-web'
    [string] $desktop = 'module/core/operation/gui/src/Xmip.Operations'

    return [PSCustomObject]@{
        Root       = $root
        SystemTest = $systemTest
        Configuration = Join-Path -Path $systemTest -ChildPath (
            'configuration/Xmip-reference-environment.xmip')
        Target     = $built
        Roll       = Join-Path -Path $target -ChildPath "xmip-system-test-roll$suffix"
        Cluster    = Join-Path -Path $target -ChildPath "xmip-system-test-cluster$suffix"
        Node       = Join-Path -Path $target -ChildPath "xmip-system-test-node$suffix"
        # Each far end outside the cluster the roll starts beside the nodes
        # it runs as xmip-service, a sender or a receiver (ADR-0028,
        # amendment 2026-11-22).
        External   = Join-Path -Path $target -ChildPath "xmip-system-test-external$suffix"
        # The Work Process units the run places beside its nodes, built as
        # the crate's examples (Invoke-XmipSystemTestBuild).
        Examples   = Join-Path -Path $target -ChildPath 'examples'
        Web        = Join-Path -Path $root -ChildPath "$web$suffix"
        Desktop    = Join-Path -Path $root -ChildPath $desktop
        Extension  = Join-Path -Path $root -ChildPath 'module/core/operation/gui/vscode'
        Area       = $estate.SystemTest
        Authority  = Join-Path -Path $estate.SystemTest -ChildPath 'authority'
        Image      = Join-Path -Path $estate.SystemTest -ChildPath 'image'
        Estate     = $estate.Estate
        Demo       = $estate.Demo
        Suffix     = $suffix
    }
}

function Invoke-XmipSystemTestBuild {
    <#
        .SYNOPSIS
            Builds one System Tests binary, cargo's lines on the Verbose stream.
            Cargo is a no-op when the binary is current, so this always runs:
            a stale binary silently running yesterday's scenarios is the thing
            it prevents.

        .PARAMETER Binary
            `roll`, `cluster` or `node`. The roll spawns the cluster and the
            cluster spawns the nodes (the owner, 2026-09-19), so building the
            roll builds all three and building the cluster builds it and the
            node; the roll also starts the far ends outside the cluster, so
            building it builds their program too. Each builds the System Tests'
            Work Process unit with it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('roll', 'cluster', 'node')]
        [string] $Binary
    )

    $layout = Get-XmipSystemTestLayout
    [string] $path = switch ($Binary) {
        'roll' { $layout.Roll }
        'cluster' { $layout.Cluster }
        default { $layout.Node }
    }

    Write-Verbose "cargo build --bin $Binary in $($layout.SystemTest)"
    [string[]] $bins = @('--bin', 'xmip-system-test-node')

    if ($Binary -in 'roll', 'cluster') {
        $bins += @('--bin', 'xmip-system-test-cluster')
    }

    if ($Binary -eq 'roll') {
        $bins += @('--bin', 'xmip-system-test-roll', '--bin', 'xmip-system-test-external')
    }

    # The Work Process unit the cluster's file names, built beside them: the
    # run copies it from there beside each node the placement runs it on
    # (configuration/order-approval.bpmn; ADR-0066 clause 4).
    $bins += @('--example', 'order_approval')

    # Cargo's first error is kept, so a failed build says why in its own
    # words and not only its exit code (Get-XmipTestStatus shows it).
    [string[]] $measured = @('--profile', $script:XmipMeasuredProfile) + $bins
    [hashtable] $building = @{ Directory = $layout.SystemTest; Argument = $measured }
    [string] $was = $env:CARGO_TARGET_DIR
    $env:CARGO_TARGET_DIR = $layout.Target

    try {
        [pscustomobject] $built = Invoke-XmipCargoBuild @building
    }
    finally {
        $env:CARGO_TARGET_DIR = $was
    }
    $built.Said | ForEach-Object { Write-Verbose $_ }
    [string] $first = @($built.Said | Where-Object { $_ -match '^error' } |
        Select-Object -First 1) -join ''

    if (-not $built.Passed) {
        [string] $why = if ($first -ne '') { ": $first" } else { '.' }
        throw "cargo build --bin $Binary failed in $($layout.SystemTest)$why"
    }

    return $path
}

function Invoke-XmipCargoBuild {
    <#
        .SYNOPSIS
            cargo build in a crate's directory, and what Invoke-XmipTool says
            of it, cargo's lines kept.

        .DESCRIPTION
            The estate is one workspace whose crates depend on each other by
            path, each its working tree (ADR-0016, amendment 2026-11-20;
            ADR-0005, amendment 2026-11-28), so a build tests what is here
            and never only what was pushed. The System Tests' binaries and
            the demo readiness check's language server are built by it.

        .PARAMETER Directory
            The crate's directory.

        .PARAMETER Argument
            What follows `cargo build`: the profile, the targets, and any
            message format.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Directory,

        [Parameter(Mandatory)]
        [string[]] $Argument
    )

    [string[]] $building = @('build') + $Argument
    Push-Location -LiteralPath $Directory

    try {
        return Invoke-XmipTool -Tool cargo -Argument $building -Output Keep
    }
    finally {
        Pop-Location
    }
}

function Invoke-XmipSystemTestService {
    <#
        .SYNOPSIS
            Builds the xmip-service a run of `Cluster` starts its nodes as, and
            says where it is.

        .DESCRIPTION
            Built as the personal-computer site builds it (Build-XmipService):
            every stage, Xmip Storage and the file transport, in the estate's
            one workspace and its `measured` build, the one the millisecond
            rule is measured on (ADR-0018, amendment 2026-11-20). The binary
            is copied to .local-work/system-test/service/<cluster>, so a later
            build never changes what a running roll's nodes run (ADR-0028,
            amendment 2026-10-22).

        .PARAMETER Cluster
            The run's cluster.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster
    )

    $layout = Get-XmipSystemTestLayout
    [string[]] $measured = @('--profile', $script:XmipMeasuredProfile)
    $null = Build-XmipService -Site personal-computer -CargoArgument $measured

    $binary = Get-XmipPackageBinary -Root $layout.Root -CargoArgument $measured
    [string] $built = Join-Path -Path $binary.Target -ChildPath (
        "$($binary.Folder)/xmip-service$($layout.Suffix)")
    [string] $folder = Join-Path -Path $layout.Area -ChildPath "service/$Cluster"
    $null = New-Item -ItemType Directory -Path $folder -Force
    [string] $kept = Join-Path -Path $folder -ChildPath "xmip-service$($layout.Suffix)"
    Copy-Item -LiteralPath $built -Destination $kept -Force

    return $kept
}


function Get-XmipSystemTestPublication {
    <#
        .SYNOPSIS
            Where the roll of a cluster publishes its snapshot, history and
            activity in an area, as the roll itself says.

        .DESCRIPTION
            The names are the System Tests' to decide (environment.rs,
            publish_paths), so this asks the roll binary —
            `xmip-system-test-roll --publication <cluster> <area>`, which
            prints them and starts nothing — rather than naming the files a
            second time. Refused in words when the roll cannot answer.

        .PARAMETER Roll
            The roll binary, from Invoke-XmipSystemTestBuild.

        .PARAMETER Cluster
            The cluster the roll rolls as.

        .PARAMETER Path
            The area the roll publishes in, as XMIP_SYSTEM_TEST_AREA tells it.
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
