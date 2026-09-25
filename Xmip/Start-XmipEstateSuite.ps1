#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Starting a run of the estate's Pester suite: detached, in a pwsh of its own, recorded.

.DESCRIPTION
    Apart from Start-XmipTestSuiteGroup.ps1 since 2026-09-25, when the estate's
    suite stopped blocking the console and began to run as a roll runs: Start
    starts, Get-XmipTestStatus observes, Stop-XmipTest stops. What reads a run's
    record is Get-XmipEstateRun.ps1; what the run writes when it ends is
    Complete-XmipEstateRun.ps1.

    Style: doc/governance/powershell-style.md
#>


function Start-XmipEstateSuite {
    <#
        .SYNOPSIS
            Starts the estate's Pester suite under test/ in a pwsh of its own,
            detached, and returns the run at once — as a roll starts.

        .DESCRIPTION
            It ran in a thread job and waited for it until 2026-09-25, when
            the owner's console was held for ten minutes by a run he could
            neither watch nor stop. Now it is a roll's shape: Start starts,
            Get-XmipTestStatus observes, Get-XmipTestResult -Suite Core.Estate
            reads what failed, Stop-XmipTest stops (the owner, 2026-09-12:
            nothing starts itself).

            The run is `pwsh -NoProfile` from this session's own $PSHOME, with
            no window on Windows, so it outlives the console that started it
            and does not share its runspace: the test files remove the Xmip
            module and import it afresh, which tore down the module running
            them when they ran inside it (2026-09-12). Its output goes to
            `estate-<start time>.log` under .local-work/estate, and its
            record beside it (Get-XmipEstateRun) says what was started and,
            once Pester returns, the verdict the run wrote itself.

            `Invoke-Pester -Path ./test` finds nothing since 2026-09-11: the
            estate's test files carry the singular suffix `.Test.ps1` and
            Pester looks for the plural. Get-XmipPesterConfiguration tells it,
            the same configuration the landing gate uses. The landing gate
            does not come through here: it runs a module's Pester tests with
            Invoke-Pester in Test-XmipDotnetModule and waits, because a gate
            needs its verdict before it lands anything.

        .PARAMETER Path
            The directory of tests. Defaults to test/ under the repository.

        .PARAMETER Test
            The test files to run, by name without the suffix: Rust.Style runs
            test/Rust.Style.Test.ps1. Omit for every file — nothing named is
            the whole suite, and Test-XmipWholeSuite is where that is decided.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter()]
        [string] $Path,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Test = @()
    )

    $layout = Get-XmipPlaygroundLayout

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path -Path $layout.Root -ChildPath 'test'
    }

    # Refused here, before anything starts, as a pattern matching nothing is
    # everywhere else (ADR-0059 clause 7).
    [string[]] $named = @()

    if (-not (Test-XmipWholeSuite -Test $Test)) {
        [string[]] $known = @(
            Get-ChildItem -LiteralPath $Path -Filter '*.Test.ps1' -File |
                ForEach-Object { $_.Name -replace '\.Test\.ps1$', '' } |
                Sort-Object
        )
        $named = @(Expand-XmipTestName -Test $Test -Known $known)
    }

    [string] $area = $layout.Estate
    New-Item -ItemType Directory -Path $area -Force | Out-Null
    Remove-XmipEstateFinished -Path $area

    [string] $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    [hashtable] $run = @{
        Record = Join-Path -Path $area -ChildPath "estate-$stamp.toml"
        Suite  = $script:XmipEstateSuite
        Path   = (Resolve-Path -LiteralPath $Path).ProviderPath
        Test   = $named
        Log    = Join-Path -Path $area -ChildPath "estate-$stamp.log"
    }

    [string] $shell = Join-Path -Path $PSHOME -ChildPath "pwsh$($layout.Suffix)"
    [string] $script = New-XmipEstateCommand @run
    [string] $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))

    $launch = @{
        FilePath               = $shell
        ArgumentList           = @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
        WorkingDirectory       = $layout.Root
        RedirectStandardOutput = $run.Log
        RedirectStandardError  = [System.IO.Path]::ChangeExtension($run.Log, '.err')
        PassThru               = $true
    }

    if ($IsWindows) {
        $launch.WindowStyle = 'Hidden'
    }

    $process = Start-Process @launch

    Write-XmipEstateStart @run -Id $process.Id -Started $process.StartTime

    [string] $what = if ($named.Count -gt 0) { $named -join ', ' } else { 'every file' }
    Write-Host ("Started $($run.Suite) ($what of $($run.Path)) as pid $($process.Id), " +
        "in its own pwsh, detached. Log: $($run.Log). Get-XmipTestStatus says how it " +
        "stands, Get-XmipTestResult -Suite $($run.Suite) what failed, and Stop-XmipTest " +
        "-Id $($process.Id) stops it.")

    return Get-XmipEstateRun -Path $area | Where-Object { $_.Id -eq $process.Id }
}


function New-XmipEstateCommand {
    <#
        .SYNOPSIS
            The script a detached estate run executes in its own pwsh.

        .DESCRIPTION
            Every value is written into it as a single-quoted literal, so no
            path or name is ever parsed as code. The run imports Xmip for the
            Pester configuration, runs Pester at its own top level — never
            inside the module, whose test files remove and re-import it — and
            then imports Xmip afresh to write its verdict with
            Complete-XmipEstateRun.

        .PARAMETER Record
            The run record's path.

        .PARAMETER Suite
            The suite's canonical name.

        .PARAMETER Path
            The directory of Pester tests.

        .PARAMETER Test
            The test files named, without the suffix; none for every file.

        .PARAMETER Log
            The run's log.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Record,

        [Parameter(Mandatory)]
        [string] $Suite,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Test = @(),

        [Parameter(Mandatory)]
        [string] $Log
    )

    [scriptblock] $quote = { param([string] $Text) "'" + ($Text -replace "'", "''") + "'" }
    [string] $manifest = & $quote (Join-Path -Path $PSScriptRoot -ChildPath 'Xmip.psd1')
    [string] $tests = '@(' + (@($Test | ForEach-Object { & $quote $_ }) -join ', ') + ')'
    [string[]] $files = @(
        $Test | ForEach-Object { Join-Path -Path $Path -ChildPath "$_.Test.ps1" }
    )
    [string] $paths = '@(' + (@($files | ForEach-Object { & $quote $_ }) -join ', ') + ')'

    return @(
        '$ErrorActionPreference = ''Stop'''
        "Import-Module -Name $manifest"
        "`$run = @{ Record = $(& $quote $Record); Suite = $(& $quote $Suite)"
        "    Path = $(& $quote $Path); Test = $tests; Log = $(& $quote $Log) }"
        '$configuration = & (Get-Module -Name Xmip) {'
        '    param($Path) Get-XmipPesterConfiguration -Path $Path } $run.Path'
        "[string[]] `$files = $paths"
        'if ($files.Count -gt 0) { $configuration.Run.Path = $files }'
        '$configuration.Output.Verbosity = ''Normal'''
        '$result = $null'
        '$fault = '''''
        'try { $result = Invoke-Pester -Configuration $configuration }'
        'catch { $fault = "$_" }'
        'Get-Module -Name Xmip -All | Remove-Module -Force -ErrorAction SilentlyContinue'
        "Import-Module -Name $manifest -Force"
        '& (Get-Module -Name Xmip | Select-Object -First 1) {'
        '    param($Run, $Result, $Fault)'
        '    Complete-XmipEstateRun @Run -Result $Result -Fault $Fault'
        '} $run $result $fault'
    ) -join [Environment]::NewLine
}


function Write-XmipEstateStart {
    <#
        .SYNOPSIS
            Writes the record of an estate run just started: what, where, and
            the pid Stop-XmipTest ends.

        .DESCRIPTION
            Written only if the run has not already written its verdict there,
            so the console can never overwrite a result. The run cannot finish
            before this — it has a module to import and Pester to load — but a
            record that cannot be clobbered does not have to rely on it.

        .PARAMETER Record
            The run record's path.

        .PARAMETER Suite
            The suite's canonical name.

        .PARAMETER Path
            The directory of Pester tests.

        .PARAMETER Test
            The test files named, without the suffix.

        .PARAMETER Log
            The run's log.

        .PARAMETER Id
            The run's process id.

        .PARAMETER Started
            When the run's process started.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Record,

        [Parameter(Mandatory)]
        [string] $Suite,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Test = @(),

        [Parameter(Mandatory)]
        [string] $Log,

        [Parameter(Mandatory)]
        [int] $Id,

        [Parameter(Mandatory)]
        [datetime] $Started
    )

    $written = [ordered]@{
        suite   = $Suite
        pid     = $Id
        started = $Started.ToUniversalTime().ToString('o')
        path    = $Path
        tests   = @($Test)
        log     = $Log
    }

    Import-Module PSToml -ErrorAction Stop

    [string] $text = ConvertTo-Toml -InputObject $written -Depth 4

    try {
        Out-File -InputObject $text -LiteralPath $Record -Encoding utf8 -NoClobber -ErrorAction Stop
    }
    catch {
        if (-not (Test-Path -LiteralPath $Record)) {
            throw
        }

        Write-Verbose "the run wrote $Record before its start was recorded; its verdict stands"
    }
}


function Remove-XmipEstateFinished {
    <#
        .SYNOPSIS
            Deletes the records and logs of estate runs that have ended, so a
            new run is the one Get-XmipTestStatus and Get-XmipTestResult read.
            A run still running is left alone.

        .PARAMETER Path
            Where the records are.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    foreach ($run in @(Get-XmipEstateRun -Path $Path)) {
        if ($run.State -eq 'running' -or -not $PSCmdlet.ShouldProcess($run.Record, 'Remove')) {
            continue
        }

        [string] $err = [System.IO.Path]::ChangeExtension($run.Log, '.err')

        foreach ($left in @($run.Record, $run.Log, $err)) {
            if (-not [string]::IsNullOrWhiteSpace($left)) {
                Remove-Item -LiteralPath $left -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

