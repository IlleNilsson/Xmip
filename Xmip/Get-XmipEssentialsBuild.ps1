#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    An Essentials roll that is still building, as its build record says it.

.DESCRIPTION
    A roll builds before it rolls, and since 2026-10-13 the build runs detached
    as the roll does: the owner, that day, of Start-XmipTest holding his console
    during the first build. Start-XmipEssentialsBuild starts it and writes one
    record per build, build-<start time>.toml, in the roll area; the build
    removes it once the roll it spawned has its own run record, or writes into
    it why it FAILED. Get-XmipTestStatus lists what is here beside the rolls;
    Stop-XmipTest stops a build as it stops an estate run.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipEssentialsBuild {
    <#
        .SYNOPSIS
            Every recorded Essentials build in a roll area, as the
            Xmip.TestStatus objects Get-XmipTestStatus lists.

        .DESCRIPTION
            State is said in words: building while the build's own pwsh is
            alive, with Tally saying how far cargo has come; FAILED with the
            reason in Fault and Tally once the build wrote one, or when its
            pwsh is gone and it wrote nothing — stopped, or died. A build that
            started its roll leaves no record, and the roll is listed instead.

        .PARAMETER Path
            The roll area.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    foreach ($read in @(Read-XmipRunRecord -Path $Path -Kind build)) {
        ConvertTo-XmipEssentialsBuild -Record $read.Record -File $read.File -Area $Path
    }
}


function ConvertTo-XmipEssentialsBuild {
    <#
        .SYNOPSIS
            One build record as an Xmip.TestStatus of kind build.

        .PARAMETER Record
            The record, as Read-XmipToml read it.

        .PARAMETER File
            The record's own path.

        .PARAMETER Area
            The roll area it is in.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Record,

        [Parameter(Mandatory)]
        [string] $File,

        [Parameter(Mandatory)]
        [string] $Area
    )

    [string] $log = [string](Get-TomlValue -Node $Record -Name 'log' -Default '')
    [hashtable] $read = @{
        Record  = $Record
        Running = 'building'
        Ended   = ('The build ended without starting its roll: it was stopped, or its ' +
            "pwsh died. $([System.IO.Path]::ChangeExtension($log, '.err')) says why.")
    }
    $run = Resolve-XmipDetachedRun @read

    # A build writes a verdict only where it FAILED: one that started its
    # roll has given way to the roll's record.
    [string] $state = if ($run.State -eq 'building') { 'building' } else { 'FAILED' }
    [string] $fault = $run.Fault
    [string] $tally = if ($state -eq 'building') {
        Get-XmipEssentialsBuildProgress -Log $log
    }
    else {
        $fault
    }

    [hashtable] $row = @{
        Suite    = [string](Get-TomlValue -Node $Record -Name 'suite' -Default '')
        Kind     = 'build'
        State    = $state
        Id       = $run.Id
        Property = @{
            Cluster     = [string](Get-TomlValue -Node $Record -Name 'cluster' -Default '')
            StartTime   = $run.Started.ToLocalTime()
            Stress      = Get-TomlValue -Node $Record -Name 'stress'
            Tests       = @(Get-TomlValue -Node $Record -Name 'tests' -Default @())
            Rounds      = [int](Get-TomlValue -Node $Record -Name 'rounds' -Default 0)
            Nodes       = @(Get-TomlValue -Node $Record -Name 'nodes' -Default @())
            OnlineNodes = @(Get-TomlValue -Node $Record -Name 'online' -Default @())
            Tally       = $tally
            Fault       = $fault
            Snapshot    = [string](Get-TomlValue -Node $Record -Name 'snapshot' -Default '')
            Path        = $Area
            Record      = $File
            Log         = $log
            Hidden      = [bool](Get-TomlValue -Node $Record -Name 'hidden' -Default $false)
        }
    }

    return (New-XmipTestStatus @row)
}


function Get-XmipEssentialsBuildProgress {
    <#
        .SYNOPSIS
            How far a running build has come, in words, from cargo's lines in
            its log: how many crates it has compiled and the last of them.

        .DESCRIPTION
            Cargo prints no total when its output is not a terminal, so this
            counts what it has done rather than inventing a percentage. The
            log is read while the build still writes it, sharing the file;
            one that cannot be read yet says building and no more.

        .PARAMETER Log
            The build's log.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Log
    )

    [string] $text = ''

    try {
        [System.IO.FileStream] $stream = [System.IO.FileStream]::new(
            $Log, 'Open', 'Read', 'ReadWrite')
        [System.IO.StreamReader] $reader = [System.IO.StreamReader]::new($stream)

        try {
            $text = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    catch {
        return 'building'
    }

    [string[]] $compiled = @(
        [regex]::Matches($text, '(?m)^\s*Compiling\s+(\S+)') |
            ForEach-Object { $_.Groups[1].Value }
    )

    [string] $crates = if ($compiled.Count -eq 1) { '1 crate' } else { "$($compiled.Count) crates" }

    if ($text -match '(?m)^\s*Finished\s') {
        return "built $crates; starting the roll"
    }

    if ($compiled.Count -eq 0) {
        return 'building'
    }

    return "building: $crates compiled, last $($compiled[-1])"
}


function Remove-XmipEssentialsBuildEnded {
    <#
        .SYNOPSIS
            Deletes what the ended builds of one cluster left — record, log
            and handed-over start — so a new start of that cluster is the one
            Get-XmipTestStatus lists. A build still running is left alone, and
            is refused by the caller instead.

        .PARAMETER Path
            The roll area.

        .PARAMETER Cluster
            The cluster about to start.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Cluster
    )

    foreach ($build in @(Get-XmipEssentialsBuild -Path $Path)) {
        if ($build.State -eq 'building' -or $build.Cluster -ne $Cluster) {
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($build.Record, 'Remove')) {
            continue
        }

        [string] $stem = $build.Record -replace '\.toml$', ''

        foreach ($extension in 'toml', 'log', 'err', 'clixml') {
            Remove-Item -LiteralPath "$stem.$extension" -Force -ErrorAction SilentlyContinue
        }
    }
}
