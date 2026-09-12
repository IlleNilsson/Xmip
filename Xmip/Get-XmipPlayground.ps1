#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipPlayground {
    <#
        .SYNOPSIS
            The Playground rolls running on this machine: one object per roll,
            with what it was started with and how it stands.

        .DESCRIPTION
            Reads the run records Start-XmipPlayground wrote under -Path and
            keeps the ones whose process is alive and is the Playground's own
            roll binary — never a process that merely shares the name. A roll
            started by hand (`cargo run --bin roll`) has no record and is
            listed with what a process alone can tell.

            Nothing here starts, stops or writes anything. Nothing running
            means no output.

        .PARAMETER Path
            Where the run records are. Defaults to the repository's
            .local-work/playground folder, where Start-XmipPlayground writes.

        .EXAMPLE
            Get-XmipPlayground

        .EXAMPLE
            Get-XmipPlayground | Format-List
    #>
    [CmdletBinding()]
    [OutputType('Xmip.Playground')]
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

    [object[]] $nodes = @(Get-XmipPlaygroundNode)
    Import-Module PSToml -ErrorAction Stop

    foreach ($roll in $rolls) {
        [string] $recordPath = Join-Path -Path $Path -ChildPath "roll-$($roll.Id).toml"
        $record = $null

        if (Test-Path -LiteralPath $recordPath) {
            $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Toml
        }

        [int] $fleet = @($nodes | Where-Object { $_.Parent -eq $roll.Id }).Count
        [string] $snapshot = if ($null -ne $record) { $record.snapshot } else { '' }
        $worst = if (Test-Path -LiteralPath $snapshot) {
            Get-XmipPlaygroundResult -Path $snapshot -Worst
        }

        [PSCustomObject]@{
            PSTypeName = 'Xmip.Playground'
            Id         = $roll.Id
            StartTime  = $roll.StartTime
            Stress     = if ($null -ne $record) { $record.stress } else { $null }
            Scenarios  = if ($null -ne $record) { @($record.scenarios) } else { @() }
            Rounds     = if ($null -ne $record) { [int] $record.rounds } else { 0 }
            Nodes      = $fleet
            Online     = if ($null -ne $record) { [bool] $record.online } else { $null }
            Worst      = if ($null -ne $worst) { $worst.State } else { $null }
            Snapshot   = $snapshot
            Path       = if ($null -ne $record) { $Path } else { $null }
            Log        = if ($null -ne $record) { $record.log } else { $null }
        }
    }
}
