#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The demo readiness check's desktop part: the Desktop operations app
    built, started over the roll's snapshot and up for a minute.

.DESCRIPTION
    The app reads gui.toml beside its executable (MauiProgram.Desktop.cs), so
    the check writes that deployed copy — Surface = "snapshot" and Snapshot =
    the roll's — and never the source file the build deploys it from; the
    stop part gives the deployed copy back as the build deploys it (ADR-0028,
    amendment 2026-11-10). The app is the Windows build alone, as every
    build is for now (ADR-0014, amendment 2026-11-02).

    What is proved is that the app starts over that document and stays up,
    nothing more: the app records no surface or snapshot it opened — its
    process declaration names the runtime library, and its audit its start —
    and with a path it cannot read it says so on its page and stays up
    (gui.toml), so whether it read the snapshot is not seen from outside it.

    Style: doc/governance/powershell-style.md
#>


# The Desktop operations app's one framework while builds are Windows only.
[string] $script:XmipDemoDesktopFramework = 'net11.0-windows10.0.19041.0'

# How long the app must stay up over the snapshot to be said OK.
[timespan] $script:XmipDemoDesktopUp = [timespan]::FromMinutes(1)


function Test-XmipDemoDesktop {
    <#
        .SYNOPSIS
            Builds the Desktop operations app, points its deployed gui.toml at
            the run's snapshot, starts it and watches it stay up; returns
            what it found in words, or throws why not.

        .PARAMETER Run
            The run, from New-XmipDemoState: its snapshot, and where the app
            and the document it launched are kept.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Run
    )

    if (-not $IsWindows) {
        throw ('the Desktop operations app is built for Windows alone, as every build is ' +
            'for now; this machine is not Windows.')
    }

    $layout = Get-XmipEssentialsLayout
    [string] $program = Build-XmipDemoDesktop -Project $layout.Desktop
    [string] $folder = Split-Path -Path $program -Parent
    [string] $deployed = Join-Path -Path $folder -ChildPath 'gui.toml'
    [string] $source = Join-Path -Path $layout.Desktop -ChildPath 'gui.toml'

    $Run['launched']['document'] = $deployed
    $Run['launched']['source'] = $source
    Write-XmipDemoRecord -Run $Run
    Set-XmipDemoDocument -Source $source -Deployed $deployed -Snapshot $Run['snapshot']

    $process = Start-XmipDemoDesktop -Program $program
    $Run['launched']['desktop'] = [int] $process.Id
    $Run['launched']['desktop_started'] = $process.StartTime.ToUniversalTime().ToString('o')
    $Run['launched']['desktop_program'] = $program
    Write-XmipDemoRecord -Run $Run

    try {
        Wait-XmipDemoUp -Process $process -For $script:XmipDemoDesktopUp
    }
    catch {
        # Ended by itself: its pid is the system's to give again, and the
        # stop part must never end what was given it.
        $Run['launched']['desktop'] = 0
        Write-XmipDemoRecord -Run $Run
        throw
    }

    return ("built, started as pid $($process.Id) with $deployed naming " +
        "$($Run['snapshot']), and stayed up for $($script:XmipDemoDesktopUp); that it read " +
        'the snapshot is not proved, since the app records no surface it opened')
}


function Build-XmipDemoDesktop {
    <#
        .SYNOPSIS
            Builds the Desktop operations app and returns the program the
            build wrote; throws with the build's first error.

        .DESCRIPTION
            dotnet build -getProperty:TargetPath says where the build put the
            app once it has built, so the check names no output folder of
            its own; the program is that assembly's executable beside it.

        .PARAMETER Project
            The app's project folder.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Project
    )

    [string[]] $building = @(
        'build', $Project, '-f', $script:XmipDemoDesktopFramework, '--nologo'
        '-getProperty:TargetPath'
    )
    [pscustomobject] $built = Invoke-XmipTool -Tool dotnet -Argument $building -Output Keep
    [string[]] $said = @($built.Said | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if (-not $built.Passed) {
        [string] $first = @($said | Where-Object { $_ -match '\berror\b' }) +
            @($said) | Select-Object -First 1

        throw "the Desktop operations app did not build: $first"
    }

    [string] $target = Select-XmipBuiltTarget -Said $said
    [string] $program = if ($target -ne '') { [System.IO.Path]::ChangeExtension($target, '.exe') }

    if ($target -eq '' -or -not (Test-Path -LiteralPath $program -PathType Leaf)) {
        throw ("the Desktop operations app built, and dotnet named no program that is " +
            "there ('$program'); it said: $($said -join ' | ')")
    }

    return $program
}


function Select-XmipBuiltTarget {
    <#
        .SYNOPSIS
            The assembly dotnet build -getProperty:TargetPath named, from
            every line it said: the last that is a whole, rooted path to a
            .dll that is there; empty where none is.

        .DESCRIPTION
            Invoke-XmipTool keeps standard error in the same lines, so a
            warning or a notice — MSBuild's, or the SDK's about workloads —
            may come before or after the value and is never taken for it.

        .PARAMETER Said
            dotnet's lines.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Said
    )

    [string[]] $paths = @(
        $Said | ForEach-Object { "$_".Trim() } | Where-Object {
            $_.EndsWith('.dll', [System.StringComparison]::OrdinalIgnoreCase) -and
                [System.IO.Path]::IsPathFullyQualified($_) -and
                (Test-Path -LiteralPath $_ -PathType Leaf)
        }
    )

    return $(if ($paths.Count -gt 0) { $paths[-1] } else { '' })
}


function Set-XmipDemoDocument {
    <#
        .SYNOPSIS
            Writes the app's deployed gui.toml from the source the build
            deploys it from, its [Xmip] table reading the snapshot: Surface =
            "snapshot", Snapshot = its full path. Every other key is the
            source's. REFUSED where the two paths are one file.

        .PARAMETER Source
            The gui.toml the build deploys.

        .PARAMETER Deployed
            The copy beside the app's executable, which the app reads.

        .PARAMETER Snapshot
            The snapshot the app is to read.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Source,

        [Parameter(Mandatory)]
        [string] $Deployed,

        [Parameter(Mandatory)]
        [string] $Snapshot
    )

    if (Test-XmipSamePath -Left $Source -Right $Deployed) {
        throw ("REFUSED. $Deployed is the source gui.toml; the check writes the deployed " +
            'copy beside the program, never the source.')
    }

    # Copied key by key, whichever shape PSToml returned (Read-XmipToml).
    $document = ConvertTo-XmipTomlTable -Node (Read-XmipToml -Path $Source)

    if ($document['Xmip'] -isnot [System.Collections.IDictionary]) {
        $document['Xmip'] = [ordered]@{}
    }

    $document['Xmip']['Surface'] = 'snapshot'
    $document['Xmip']['Snapshot'] = [System.IO.Path]::GetFullPath($Snapshot)

    if ($PSCmdlet.ShouldProcess($Deployed, "Point at $Snapshot")) {
        Write-XmipToml -Path $Deployed -Value $document
    }
}


function Wait-XmipDemoUp {
    <#
        .SYNOPSIS
            Watches a process stay up for a while; throws, saying when and
            with what exit code, where it ends before.

        .PARAMETER Process
            The process, as Start-XmipDemoDesktop returned it.

        .PARAMETER For
            How long it must stay up.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process,

        [Parameter(Mandatory)]
        [timespan] $For
    )

    [System.Diagnostics.Stopwatch] $clock = [System.Diagnostics.Stopwatch]::StartNew()

    while ($clock.Elapsed -lt $For) {
        if ($Process.HasExited) {
            [int] $seconds = [int] $clock.Elapsed.TotalSeconds

            throw ("it ended $seconds s after it started, exit code $($Process.ExitCode); " +
                'its audit and the operating system''s log say why.')
        }

        Start-Sleep -Milliseconds 500
    }
}
