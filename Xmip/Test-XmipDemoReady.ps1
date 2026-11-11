#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What a run of Core.Demo, the demo readiness check, does in its own pwsh:
    each part in turn, said OK, FAILED or SKIPPED in words with the reason,
    then everything it started stopped, whatever failed.

.DESCRIPTION
    Started by Start-XmipDemoSuite, never by the console that asked for it
    (ADR-0028, amendment 2026-11-10). The parts are what the owner's demo
    runs: the Essentials roll (Test-XmipDemoRoll.ps1), the web operations
    tool over it (Test-XmipDemoWeb.ps1), the Desktop operations app over the
    same snapshot (Test-XmipDemoDesktop.ps1) and the VS Code extension with
    its language server (Test-XmipDemoExtension.ps1); last, stop, which ends
    what the run started (Stop-XmipDemoStarted.ps1). A part that reads the
    roll is SKIPPED, saying so, where the roll did not come up; the run is OK
    only where every part is.

    The record, demo-<start time>.toml, is written whole after every launch
    and every part: Get-XmipTestStatus says which part runs, Get-XmipTestResult
    -Suite Core.Demo what each said, and Stop-XmipTest finds in it what to
    stop. The console writes it once, at the start, and never again, so the
    two never race over one file.

    Style: doc/governance/powershell-style.md
#>


# The stress the check rolls at where -Stress is not given: the demo's own,
# Realistic (the coordinator's brief, 2026-11-10), never the Essentials'
# hardest, which is the roll's rule for a roll asked for by itself.
[string] $script:XmipDemoStress = 'Realistic'


function Test-XmipDemoReady {
    <#
        .SYNOPSIS
            Runs the demo readiness check and writes its verdict into its
            record, stopping everything it started however it ends.

        .PARAMETER Record
            The run's record.

        .PARAMETER Cluster
            The cluster to roll.

        .PARAMETER Stress
            The stress the roll is started at; Realistic, the demo's own,
            where it is not given.

        .PARAMETER Tester
            The person the web host lets act, as Start-XmipOperationWeb
            -Tester takes them; empty for none.

        .PARAMETER Hidden
            The run, and a roll it starts, declared hidden.

        .PARAMETER Log
            The run's log.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Record,

        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter()]
        [ValidateNotNullOrWhiteSpace()]
        [string] $Stress = $script:XmipDemoStress,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Tester = '',

        [Parameter()]
        [switch] $Hidden,

        [Parameter(Mandatory)]
        [string] $Log
    )

    $ErrorActionPreference = 'Stop'
    [datetime] $began = (Get-Process -Id $PID).StartTime
    $state = New-XmipDemoState @PSBoundParameters -Id $PID -Started $began
    [hashtable] $said = @{
        Cluster = $Cluster
        Stress  = $Stress
        Tester  = $Tester
        Hidden  = [bool] $Hidden
    }
    Write-XmipAudit -Action 'Test-XmipDemoReady' -Phase Begin -Property $said
    Write-XmipDemoRecord -Run $state
    [string] $broke = ''

    try {
        $roll = Test-XmipDemoPart -Run $state -Name 'roll' -Check { Test-XmipDemoRoll -Run $state }

        # The web host and the desktop app read the snapshot the roll
        # publishes; one failing never keeps the other from being tried.
        if ($roll.State -eq 'OK') {
            $null = Test-XmipDemoPart -Run $state -Name 'web' -Check {
                Test-XmipDemoWeb -Run $state
            }
            $null = Test-XmipDemoPart -Run $state -Name 'desktop' -Check {
                Test-XmipDemoDesktop -Run $state
            }
        }
        else {
            [string] $why = "Not tried: the roll part did not pass ($($roll.Reason))."

            foreach ($name in 'web', 'desktop') {
                Add-XmipDemoPart -Run $state -Part (
                    New-XmipDemoPart -Name $name -State 'SKIPPED' -Reason $why)
            }
        }

        $null = Test-XmipDemoPart -Run $state -Name 'extension' -Check {
            Test-XmipDemoExtension -Run $state
        }
    }
    catch {
        # A run that breaks off is FAILED, whatever its parts said so far.
        $broke = $_.Exception.Message
        throw
    }
    finally {
        Complete-XmipDemoRun -Run $state -Broke $broke
    }
}


function New-XmipDemoState {
    <#
        .SYNOPSIS
            A run of the check as its record holds it: what it was started
            with, what it launched, and its parts so far. The one shape the
            console's first write and every write of the run share.

        .DESCRIPTION
            Every scalar key is there from the start, so the record's order
            never changes: launched names what Stop-XmipTest ends — roll the
            cluster the run started and roll_ids the pids of its build and
            its roll, so a roll of that cluster another started is never
            stopped; web the host's pid; desktop the app's
            pid, with desktop_started and desktop_program, so a pid the
            system gave another process since is never stopped; document the
            desktop app's deployed gui.toml and source the file the build
            deploys it from.

        .PARAMETER Record
            The run's record.

        .PARAMETER Cluster
            The cluster it rolls.

        .PARAMETER Stress
            The stress it starts the roll at.

        .PARAMETER Tester
            The tester, or empty.

        .PARAMETER Hidden
            Whether the run is declared hidden.

        .PARAMETER Log
            The run's log.

        .PARAMETER Id
            The run's process id.

        .PARAMETER Started
            When the run's process started.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string] $Record,

        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter()]
        [ValidateNotNullOrWhiteSpace()]
        [string] $Stress = $script:XmipDemoStress,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Tester = '',

        [Parameter()]
        [switch] $Hidden,

        [Parameter(Mandatory)]
        [string] $Log,

        [Parameter(Mandatory)]
        [int] $Id,

        [Parameter(Mandatory)]
        [datetime] $Started
    )

    return [ordered]@{
        record   = $Record
        suite    = $script:XmipDemoSuite
        pid      = $Id
        started  = $Started.ToUniversalTime().ToString('o')
        cluster  = $Cluster
        stress   = $Stress
        tester   = $Tester
        hidden   = [bool] $Hidden
        log      = $Log
        doing    = ''
        snapshot = ''
        state    = ''
        finished = ''
        launched = [ordered]@{
            roll = ''; roll_ids = @(); web = 0; desktop = 0; desktop_started = ''
            desktop_program = ''; document = ''; source = ''
        }
        parts    = [System.Collections.Generic.List[object]]::new()
    }
}


function Write-XmipDemoRecord {
    <#
        .SYNOPSIS
            Writes a run's record whole, from what the run holds.

        .PARAMETER Run
            The run, from New-XmipDemoState.

        .PARAMETER NoClobber
            Write only where the run has not written its own yet: the
            console's one write, at the start.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Run,

        [Parameter()]
        [switch] $NoClobber
    )

    [System.Collections.Specialized.OrderedDictionary] $written = [ordered]@{}

    foreach ($key in @($Run.Keys | Where-Object { $_ -notin 'record', 'parts' })) {
        $written[$key] = $Run[$key]
    }

    $written['parts'] = @(
        $Run['parts'] | ForEach-Object {
            [ordered]@{ name = $_.Name; state = $_.State; reason = $_.Reason }
        }
    )

    Write-XmipToml -Path $Run['record'] -Value $written -NoClobber:$NoClobber
}


# A part is run and added to the run by New-XmipDemoPart.ps1's
# Test-XmipDemoPart and Add-XmipDemoPart (2026-11-10).


function Complete-XmipDemoRun {
    <#
        .SYNOPSIS
            Ends a run: says the part it broke off in FAILED where it broke
            off, stops what it launched, as the part stop, and writes its
            verdict — OK only where every part is OK.

        .PARAMETER Run
            The run, from New-XmipDemoState.

        .PARAMETER Broke
            Why the run broke off before its last part; empty where it did not.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Run,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Broke = ''
    )

    if ($Broke -ne '') {
        [string] $where = if ($Run['doing'] -ne '') { $Run['doing'] } else { 'run' }
        Add-XmipDemoPart -Run $Run -Part (
            New-XmipDemoPart -Name $where -State 'FAILED' -Reason "the run broke off: $Broke")
    }

    $Run['doing'] = 'stop'
    Add-XmipDemoPart -Run $Run -Part (Stop-XmipDemoStarted -Launched $Run['launched'])

    [object[]] $parts = @($Run['parts'])
    [object[]] $passed = @($parts | Where-Object { $_.State -eq 'OK' })
    [string] $verdict = if ($passed.Count -eq $parts.Count) { 'OK' } else { 'FAILED' }

    $Run['doing'] = ''
    $Run['state'] = $verdict
    $Run['finished'] = [datetime]::UtcNow.ToString('o')
    Write-XmipDemoRecord -Run $Run

    [string] $tally = "$($passed.Count) of $($parts.Count) parts OK"
    Write-Host "$verdict. $($Run['suite']) over $($Run['cluster']): $tally."

    [hashtable] $audited = @{
        Action   = 'Test-XmipDemoReady'
        Phase    = 'Finished'
        Severity = if ($verdict -eq 'OK') { 'Information' } else { 'Error' }
        Message  = "$verdict, $tally"
        Property = @{
            Cluster = $Run['cluster']
            State   = $verdict
            Hidden  = [bool] $Run['hidden']
        }
    }
    Write-XmipAudit @audited
}
