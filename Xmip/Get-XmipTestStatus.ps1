#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipTestStatus {
    <#
        .SYNOPSIS
            The Xmip test runs on this machine: one object per run, with its
            suite, what it was started with and how it stands.

        .DESCRIPTION
            The Playground is the one suite today, and a run of it is a roll.
            Reads the run records Start-XmipTest wrote under -Path and
            keeps the ones whose process is alive and is the Playground's own
            roll binary — never a process that merely shares the name. A roll
            started by hand (`cargo run --bin roll`) has no record and is
            listed with what a process alone can tell.

            Nothing here starts, stops or writes anything. Nothing running
            means no output.

        .PARAMETER Path
            Where the run records are. Defaults to the repository's
            .local-work/playground folder, where Start-XmipTest writes.

        .EXAMPLE
            Get-XmipTestStatus

        .EXAMPLE
            Get-XmipTestStatus | Format-List
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter()]
        [string] $Path
    )

    $layout = Get-XmipPlaygroundLayout

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $layout.Area
    }

    [System.Diagnostics.Process[]] $rolls = @(
        Get-Process -Name 'roll' -ErrorAction SilentlyContinue |
            Where-Object { Test-XmipPlaygroundBinary -Process $_ -Path $layout.Roll }
    )

    if ($rolls.Count -eq 0) {
        return
    }

    [object[]] $nodes = @(Get-XmipTestNode)
    Import-Module PSToml -ErrorAction Stop

    foreach ($roll in $rolls) {
        [string] $recordPath = Join-Path -Path $Path -ChildPath "roll-$($roll.Id).toml"
        $record = $null

        if (Test-Path -LiteralPath $recordPath) {
            $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Toml
        }

        [string] $snapshot = if ($null -ne $record) { $record.snapshot } else { '' }
        $worst = if (Test-Path -LiteralPath $snapshot) {
            Get-XmipTestResult -Path $snapshot -Worst
        }

        [object[]] $mine = @($nodes | Where-Object { $_.Parent -eq $roll.Id })
        [object[]] $online = @($mine | Where-Object { $_.Online })

        [PSCustomObject]@{
            PSTypeName  = 'Xmip.TestStatus'
            Suite       = 'Playground'
            Id          = $roll.Id
            StartTime   = $roll.StartTime
            Stress      = if ($null -ne $record) { $record.stress } else { $null }
            Tests       = if ($null -ne $record) { @($record.tests) } else { @() }
            Rounds      = if ($null -ne $record) { [int] $record.rounds } else { 0 }
            Nodes       = @($mine | ForEach-Object { $_.Name } | Sort-Object)
            OnlineNodes = @($online | ForEach-Object { $_.Name } | Sort-Object)
            Worst       = if ($null -ne $worst) { $worst.State } else { $null }
            Snapshot    = $snapshot
            Path        = if ($null -ne $record) { $Path } else { $null }
            Log         = if ($null -ne $record) { $record.log } else { $null }
        }
    }
}
