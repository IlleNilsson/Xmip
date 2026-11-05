#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Every `cargo test` a landing runs, and the one place a test that never ends
    fails it.

.DESCRIPTION
    On 2026-11-04 a landing stopped in module/core/library/tls at 15:19 and
    printed nothing more for two hours: seven handshake tests waited on each
    other, and libtest, which never ends a test, said only that each had been
    running for over 60 seconds. The owner: *there has to be a better way*.

    That line is the limit. The first time libtest prints it, the run is ended:
    the cargo this command started is stopped with every process beneath it,
    the test is named, and the module fails. No limit is added or lengthened;
    a test that needs a minute is a defect by the millisecond rule already
    (rust-style.md), and now it is one the landing reports in a minute, not
    one the operator finds hours later.

    Style: doc/governance/powershell-style.md
#>


# What libtest prints, once, of a test that has run for a minute.
$script:XmipHungTest = '^test (\S+) has been running for over 60 seconds'


function Invoke-XmipCargoTest {
    <#
        .SYNOPSIS
            Runs `cargo test` with the arguments given, each line written as it
            comes. Whether it passed; false at once for a test that runs a
            minute, named.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # Everything after `cargo test`: the patch, the features, and after
        # `--` the test binary's own arguments.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Argument
    )

    [string] $hung = ''
    [datetime] $started = Get-Date

    # ForEach-Object runs its block in this scope, so $hung is this one.
    & cargo test @Argument 2>&1 | ForEach-Object {
        [string] $line = $_
        Write-Host $line

        if (-not $hung -and $line -match $script:XmipHungTest) {
            $hung = $Matches[1]
            Stop-XmipCargoRun -Since $started
        }
    }
    [bool] $passed = $LASTEXITCODE -eq 0

    if ($hung) {
        [string] $said = "   FAILED. $hung ran a minute and was stopped, with the run."
        Write-Host $said -ForegroundColor Red
        return $false
    }

    $passed
}


function Stop-XmipCargoRun {
    <#
        .SYNOPSIS
            Ends every process this PowerShell started since the run began,
            and every process beneath each: cargo, its test binaries and
            whatever they started.

        .DESCRIPTION
            Found by when and by whom it was started, not by name: what this
            PowerShell starts as `cargo` is rustup's proxy, a process called
            rustup, and the cargo beneath it (2026-11-04).
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
