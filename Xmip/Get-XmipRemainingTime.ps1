#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    How far a landing's verification has come and about how long it has left.

.DESCRIPTION
    A landing of two hundred modules took over an hour on 2026-10-13 and said
    nothing about how much of it was left. The owner: *that would be a nice
    feature. A timer, letting one know how long it is going to take.*

    Style: doc/governance/powershell-style.md
#>


function Get-XmipRemainingTime {
    <#
        .SYNOPSIS
            The progress line printed before each module a landing verifies:
            where it is, and about how long is left.

        .DESCRIPTION
            Pure: counts and durations in, one sentence out. The modules left
            are estimated from the average of the modules measured so far in
            this run, or, before the first is measured, from what the same
            modules took when last verified. The root crate and test/ come
            from their last run, or are said to be not yet timed.

        .PARAMETER Index
            The module about to start, from one; one past Total for the root
            crate and test/ after the last module.

        .PARAMETER Total
            How many modules this landing verifies.

        .PARAMETER Measured
            How long each module verified so far in this run took.

        .PARAMETER Recorded
            How long the modules of this landing took when last verified.

        .PARAMETER Final
            How long the root crate and test/ took when last run; $null when
            no run of them was recorded.

        .PARAMETER FinalName
            What the final steps are called in the sentence.

        .EXAMPLE
            Get-XmipRemainingTime -Index 76 -Total 205 -Measured $times -Final $last
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int] $Index,

        [Parameter(Mandatory)]
        [int] $Total,

        [Parameter()]
        [AllowEmptyCollection()]
        [timespan[]] $Measured = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [timespan[]] $Recorded = @(),

        [Parameter()]
        [AllowNull()]
        [Nullable[timespan]] $Final = $null,

        [Parameter()]
        [string] $FinalName = 'the root crate and test/'
    )

    [timespan[]] $basis = $Recorded

    if ($Measured.Count -gt 0) {
        $basis = $Measured
    }

    [int] $left = [math]::Max(0, $Total - $Index + 1)

    [Nullable[timespan]] $modules = if ($left -eq 0) {
        [timespan]::Zero
    }
    elseif ($basis.Count -gt 0) {
        [double] $average = ($basis | Measure-Object -Property Ticks -Average).Average
        [timespan]::FromTicks([long] ($average * $left))
    }

    [string] $at = if ($Index -le $Total) {
        [int] $percent = [math]::Floor(100 * ($Index - 1) / $Total)
        "module $Index of $Total ($percent %)"
    }
    elseif ($Total -gt 0) {
        "all $Total modules done; $FinalName next"
    }
    else {
        "$FinalName next"
    }

    if ($null -eq $modules) {
        return "$at, time left unknown until a module has been timed"
    }

    if ($null -eq $Final) {
        if ($left -eq 0) {
            return "$at, time left unknown: not yet timed"
        }

        return "$at, $(Format-XmipDuration -Duration $modules) left, " +
            "and $FinalName not yet timed"
    }

    "$at, $(Format-XmipDuration -Duration ($modules + $Final)) left"
}

function Format-XmipDuration {
    <#
        .SYNOPSIS
            A duration as a person says it: under a minute, about 45 minutes,
            about 2 hours and 5 minutes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [timespan] $Duration
    )

    [int] $minutes = [math]::Round($Duration.TotalMinutes)

    if ($minutes -lt 1) {
        return 'under a minute'
    }

    if ($minutes -eq 1) {
        return 'about 1 minute'
    }

    if ($minutes -lt 120) {
        return "about $minutes minutes"
    }

    [int] $hours = [math]::Floor($minutes / 60)
    [int] $rest = $minutes % 60

    if ($rest -eq 0) {
        return "about $hours hours"
    }

    "about $hours hours and $rest minutes"
}
