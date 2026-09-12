#requires -Version 7.6.5

Set-StrictMode -Version Latest

function New-XmipPlaygroundEnvironment {
    <#
        .SYNOPSIS
            The environment a roll is started with: every switch the roll reads,
            as the variables it reads them from. Pure, so a test can hold it up
            against the roll's own documentation.

        .DESCRIPTION
            The variables are the roll's (test/playground/src/bin/roll.rs) and
            carry the xmip prefix because they are external names (ADR-0030).
            Only what the caller chose is set — an unset variable is the
            roll's own default, and a roll started by hand behaves the same.
            The three publish paths are always set, so a run lands where
            Get-XmipPlaygroundResult and the web host look.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Calm', 'Realistic', 'Harsh', 'Brutal')]
        [string] $Stress,

        [Parameter()]
        [string[]] $Scenario = @(),

        [Parameter()]
        [Nullable[int]] $Nodes,

        [Parameter()]
        [bool] $Online = $false,

        [Parameter()]
        [Nullable[timespan]] $Duration,

        [Parameter()]
        [Nullable[double]] $TimeFactor,

        [Parameter()]
        [string] $LoadBytes,

        [Parameter(Mandatory)]
        [string] $Snapshot,

        [Parameter(Mandatory)]
        [string] $History,

        [Parameter(Mandatory)]
        [string] $Activity
    )

    [hashtable] $environment = @{
        XMIP_PLAYGROUND_STRESS   = $Stress.ToLowerInvariant()
        XMIP_ONLINE              = if ($Online) { 'true' } else { 'false' }
        XMIP_PLAYGROUND_SNAPSHOT = $Snapshot
        XMIP_PLAYGROUND_HISTORY  = $History
        XMIP_PLAYGROUND_ACTIVITY = $Activity
    }

    if ($Scenario.Count -gt 0) {
        [string[]] $names = @($Scenario | ForEach-Object { $_.ToLowerInvariant() })
        $environment.XMIP_PLAYGROUND_SCENARIOS = $names -join ','
    }

    if ($null -ne $Nodes) {
        $environment.XMIP_PLAYGROUND_NODES = "$Nodes"
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture

    if ($null -ne $Duration) {
        [double] $seconds = ([timespan] $Duration).TotalSeconds
        $environment.XMIP_PLAYGROUND_MAX_SECONDS = $seconds.ToString($invariant)
    }

    if ($null -ne $TimeFactor) {
        $environment.XMIP_PLAYGROUND_TIME_FACTOR = ([double] $TimeFactor).ToString('R', $invariant)
    }

    if (-not [string]::IsNullOrWhiteSpace($LoadBytes)) {
        $environment.XMIP_PLAYGROUND_LOAD_BYTES = $LoadBytes
    }

    return $environment
}
