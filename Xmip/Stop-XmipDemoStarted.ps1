#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Stopping what a run of the demo readiness check started: the one
    implementation its own last part, stop, and Stop-XmipTest both call.

.DESCRIPTION
    A run names in its record what it launched, as it launches it
    (New-XmipDemoState): the cluster it started with the pids of its build
    and its roll, the web host, the desktop app with when it started and its
    program, and the desktop app's deployed gui.toml with the source the
    build deploys it from. Each is ended the estate's way, and only where it
    is still what the run started: the roll by Stop-XmipTest, nodes first,
    where its pid still rolls or builds as that cluster
    (Get-XmipClusterRunning); the web host by Stop-XmipOperationWeb, where
    Get-XmipOperationWeb still lists it; the desktop app by Stop-XmipProcess,
    where its pid is still that program started then (Test-XmipDetachedAlive);
    the document given back by copying its source over it. One that fails is
    said and never keeps the others from being stopped (ADR-0028, amendment
    2026-11-10).

    Style: doc/governance/powershell-style.md
#>


function Stop-XmipDemoStarted {
    <#
        .SYNOPSIS
            Stops everything a demo run launched and returns the part stop:
            OK saying what was stopped, or FAILED saying what was not and why.
            Never throws.

        .PARAMETER Launched
            The run's launched table, from its record or New-XmipDemoState.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.DemoPart')]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [System.Collections.IDictionary] $Launched
    )

    [string] $roll = [string](Get-TomlValue -Node $Launched -Name 'roll' -Default '')
    [int[]] $ours = @(Get-TomlValue -Node $Launched -Name 'roll_ids' -Default @())
    [int] $web = [int](Get-TomlValue -Node $Launched -Name 'web' -Default 0)
    [int] $desktop = [int](Get-TomlValue -Node $Launched -Name 'desktop' -Default 0)
    [string] $document = [string](Get-TomlValue -Node $Launched -Name 'document' -Default '')
    [string] $source = [string](Get-TomlValue -Node $Launched -Name 'source' -Default '')
    [System.Collections.Generic.List[string]] $said = @()
    [System.Collections.Generic.List[string]] $failed = @()

    # Named by id, never piped: an empty pipeline leaves Stop-XmipTest and
    # Stop-XmipOperationWeb their default, which is every run and every host.
    if ($roll -ne '') {
        try {
            [string] $area = (Get-XmipEssentialsLayout).Area
            [int[]] $rolling = @(
                Get-XmipClusterRunning -Path $area -Cluster $roll | Where-Object { $_ -in $ours }
            )

            if ($rolling.Count -gt 0) {
                Stop-XmipTest -Id $rolling -Confirm:$false -ErrorAction Stop
            }

            $said.Add("stopped $roll, $($rolling.Count) of its runs running")
        }
        catch {
            $failed.Add("$roll was not stopped: $($_.Exception.Message)")
        }
    }

    if ($web -gt 0) {
        try {
            [bool] $hosting = @(Get-XmipOperationWeb | Where-Object { $_.Id -eq $web }).Count -gt 0

            if ($hosting) {
                Stop-XmipOperationWeb -Id $web -Confirm:$false -ErrorAction Stop
                $said.Add("stopped the web host, pid $web")
            }
            else {
                $said.Add("the web host, pid $web, had ended")
            }
        }
        catch {
            $failed.Add("the web host, pid $web, was not stopped: $($_.Exception.Message)")
        }
    }

    if ($desktop -gt 0) {
        try {
            [string] $since = Get-TomlValue -Node $Launched -Name 'desktop_started' -Default ''
            [string] $program = Get-TomlValue -Node $Launched -Name 'desktop_program' -Default ''
            [hashtable] $same = @{
                Id      = $desktop
                Started = if ($since -ne '') { [datetime] $since } else { [datetime]::MinValue }
                Program = $program
            }

            if (Test-XmipDetachedAlive @same) {
                Stop-XmipProcess -Id $desktop -ErrorAction Stop
                $said.Add("stopped the desktop app, pid $desktop")
            }
            else {
                $said.Add("the desktop app, pid $desktop, had ended")
            }
        }
        catch {
            $failed.Add("the desktop app, pid $desktop, was not stopped: $($_.Exception.Message)")
        }
    }

    if ($document -ne '') {
        try {
            Copy-Item -LiteralPath $source -Destination $document -Force -ErrorAction Stop
            $said.Add("gave $document back as the build deploys it")
        }
        catch {
            $failed.Add("$document was not given back: $($_.Exception.Message)")
        }
    }

    if ($said.Count -eq 0 -and $failed.Count -eq 0) {
        $said.Add('it had started nothing')
    }

    [string] $state = if ($failed.Count -eq 0) { 'OK' } else { 'FAILED' }
    [string] $reason = (@($failed) + @($said)) -join '; '

    return New-XmipDemoPart -Name 'stop' -State $state -Reason $reason
}


function Stop-XmipDemoRun {
    <#
        .SYNOPSIS
            Stops what a demo run launched, as its record names it, says so
            in words, and returns the cluster whose roll it stopped, or
            nothing: Stop-XmipTest's half before it ends a running run's
            pwsh, and what is left of a run that ended without a verdict.

        .DESCRIPTION
            A run whose pwsh died or was killed outside Stop-XmipTest never
            ran its stop part, so its roll, web host, desktop app and
            rewritten gui.toml may still be there; its record still names
            them, and this stops them as the run would have.

        .PARAMETER Run
            The run, from Get-XmipTestStatus or Get-XmipDemoRun.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Run
    )

    [System.Collections.IDictionary] $launched = [ordered]@{}

    if (-not [string]::IsNullOrWhiteSpace($Run.Record) -and (Test-Path -LiteralPath $Run.Record)) {
        $read = Read-XmipToml -Path $Run.Record
        $launched = ConvertTo-XmipTomlTable -Node (
            Get-TomlValue -Node $read -Name 'launched' -Default ([ordered]@{}))
    }

    $part = Stop-XmipDemoStarted -Launched $launched
    Write-Host "$($Run.Suite) run $($Run.Id): $(Format-XmipDemoPart -Part $part)"

    return [string](Get-TomlValue -Node $launched -Name 'roll' -Default '')
}
