#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Every cargo and dotnet the module runs, and the one place what they share
    is decided: how much of the machine they take, how their lines are shown,
    whether they passed, and that a test running a minute fails.

.DESCRIPTION
    Nothing else in the module calls cargo or dotnet. The ceiling on how
    much of the machine a run takes is set here and nowhere else.

    A test that runs a minute is a defect by the millisecond rule
    (rust-style.md 5d): the first time libtest says one has, the run is ended
    with every process beneath it and the test is named.

    Style: doc/governance/powershell-style.md
#>


# How much of the machine one build or test takes: twelve, the 75 percent
# ceiling (the owner, 2026-11-02). cargo's jobs, libtest's threads and
# MSBuild's nodes all read it.
[int] $script:XmipParallel = 12

# What libtest prints, once, of a test that has run for a minute.
[string] $script:XmipHungTest = '^test (\S+) has been running for over 60 seconds'


function Invoke-XmipTool {
    <#
        .SYNOPSIS
            Runs cargo or dotnet with the arguments given and says whether it
            passed, and what it said where -Output Keep asks for it.

        .PARAMETER Tool
            `cargo` or `dotnet`.

        .PARAMETER Argument
            Everything after the tool's name: its subcommand first.

        .PARAMETER Output
            `Show` writes each line as it comes, after -Prefix; `Keep` writes
            nothing and returns the lines; `None` writes and keeps nothing.

        .PARAMETER Prefix
            What each shown line starts with, such as `     cargo| `.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('cargo', 'dotnet')]
        [string] $Tool,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Argument,

        [ValidateSet('Show', 'Keep', 'None')]
        [string] $Output = 'Show',

        [string] $Prefix = ''
    )

    [string[]] $given = @($Argument)
    [string] $subcommand = if ($given.Count -gt 0) { $given[0] } else { '' }

    [string[]] $parallel = @('build', 'test', 'publish', 'pack', 'restore')

    if ($Tool -eq 'dotnet' -and $subcommand -in $parallel -and
        -not @($given | Where-Object { $_ -like '-m:*' })) {
        $given += "-m:$script:XmipParallel"
    }

    [hashtable] $before = @{
        CARGO_BUILD_JOBS  = $env:CARGO_BUILD_JOBS
        RUST_TEST_THREADS = $env:RUST_TEST_THREADS
    }

    if ($Tool -eq 'cargo') {
        $env:CARGO_BUILD_JOBS = "$script:XmipParallel"
        $env:RUST_TEST_THREADS = "$script:XmipParallel"
    }

    [System.Collections.Generic.List[string]] $said = @()
    [string] $hung = ''
    [datetime] $started = Get-Date

    try {
        # ForEach-Object runs its block in this scope, so $hung and $said are
        # this function's.
        & $Tool @given 2>&1 | ForEach-Object {
            [string] $line = "$_"

            switch ($Output) {
                'Show' { Write-Host "$Prefix$line" }
                'Keep' { $said.Add($line) }
            }

            if ($Tool -eq 'cargo' -and -not $hung -and $line -match $script:XmipHungTest) {
                $hung = $Matches[1]
                Stop-XmipToolRun -Since $started
            }
        }
        [bool] $passed = $LASTEXITCODE -eq 0
    }
    finally {
        $env:CARGO_BUILD_JOBS = $before.CARGO_BUILD_JOBS
        $env:RUST_TEST_THREADS = $before.RUST_TEST_THREADS
    }

    if ($hung) {
        [string] $stopped = "   FAILED. $hung ran a minute and was stopped, with the run."
        Write-Host $stopped -ForegroundColor Red
        $passed = $false
    }

    [pscustomobject]@{
        Passed = $passed
        Said   = [string[]] $said.ToArray()
    }
}


function Stop-XmipToolRun {
    <#
        .SYNOPSIS
            Ends every process this PowerShell started since the run began,
            and every process beneath each: cargo, its test binaries and
            whatever they started.

        .DESCRIPTION
            Found by when and by whom it was started, not by name: what this
            PowerShell starts as `cargo` is rustup's proxy, a process called
            rustup, and the cargo beneath it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [datetime] $Since
    )

    foreach ($process in @(Get-Process)) {
        try {
            if ($process.Parent.Id -ne $PID -or $process.StartTime -lt $Since) {
                continue
            }
        }
        catch {
            # Another user's process, or one that has already ended.
            continue
        }

        if ($PSCmdlet.ShouldProcess("$($process.Name) $($process.Id)", 'Stop with its tree')) {
            $process.Kill($true)
        }
    }
}
