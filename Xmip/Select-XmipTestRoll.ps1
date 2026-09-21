#requires -Version 7.6.5

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Which running tests a set of filters picks, and when to refuse instead.

.DESCRIPTION
    Apart from Stop-XmipTest so the choosing can be tested with runs made of
    nothing but their properties, and no process started or stopped. A run is
    one process driving one or more tests, and that is the whole of the
    difficulty: a test is stopped by stopping its run, so asking to stop one
    test of a run that drives two is asking for something the estate cannot
    do without doing more. That is refused, in words, before anything is
    stopped (ADR-0055 clauses 2, 3 and 5; the owner, 2026-09-21).

    Style: doc/governance/powershell-style.md
#>

function Get-XmipTestOfRoll {
    <#
        .SYNOPSIS
            The tests one run drives, by the names Start-XmipTest takes.

        .DESCRIPTION
            What the run was started with, or, for a run started without
            -Test, every test of its suite — which is what it drives. A suite
            whose tests this cannot list, which is any but the Playground,
            drives nothing that can be named here.

        .PARAMETER Roll
            One run, from Get-XmipTestStatus.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject] $Roll
    )

    [string[]] $started = @($Roll.Tests | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($started.Count -gt 0) {
        return $started
    }

    if ("$($Roll.Suite)" -eq $script:XmipPlaygroundSuite) {
        return [string[]] @($script:XmipPlaygroundTest.Keys)
    }

    return [string[]] @()
}


function Format-XmipRollingNow {
    <#
        .SYNOPSIS
            What is running, in the words a refusal ends with.

        .PARAMETER Running
            Every run, from Get-XmipTestStatus.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Running
    )

    if ($Running.Count -eq 0) {
        return 'Nothing is rolling.'
    }

    [string[]] $said = @(
        foreach ($roll in $Running) {
            [string[]] $started = @($roll.Tests | Where-Object { "$_" -ne '' })
            [string] $drives = if ($started.Count -gt 0) {
                $started -join ', '
            }
            else {
                'the whole suite'
            }

            "$($roll.Cluster) running $drives"
        }
    )

    return "Rolling now: $($said -join '; ')."
}


function Select-XmipTestRoll {
    <#
        .SYNOPSIS
            The runs -Cluster and -Test pick together, or a refusal.

        .DESCRIPTION
            Neither given is every run. -Cluster picks by the cluster a run
            rolls as. -Test picks the runs that drive a matching test, and
            then refuses every one of them that also drives a test not
            named, since stopping it would stop that test too. Either filter
            matching nothing is refused as well, naming what is running, so a
            typo never reads as success.

            Every refusal is written before any run is chosen, so the caller
            stops nothing when anything is refused.

        .PARAMETER Running
            Every run, from Get-XmipTestStatus.

        .PARAMETER Cluster
            A cluster name or pattern; empty for any.

        .PARAMETER Test
            Test names or patterns; none for any.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Running,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Cluster,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $Test = @()
    )

    [string] $there = Format-XmipRollingNow -Running $Running
    [object[]] $rolls = $Running

    if (-not [string]::IsNullOrEmpty($Cluster)) {
        $rolls = @($Running | Where-Object { "$($_.Cluster)" -like $Cluster })

        if ($rolls.Count -eq 0) {
            Write-Error "REFUSED. No roll matches $Cluster. $there"
            return
        }
    }

    if ($Test.Count -eq 0) {
        return $rolls
    }

    [System.Collections.Generic.List[object]] $picked = @()
    [System.Collections.Generic.List[string]] $refused = @()

    foreach ($roll in $rolls) {
        [string[]] $drives = @(Get-XmipTestOfRoll -Roll $roll)
        [string[]] $named = @(
            $drives | Where-Object {
                [string] $one = $_
                @($Test | Where-Object { $one -like $_ }).Count -gt 0
            }
        )

        if ($named.Count -eq 0) {
            continue
        }

        [string[]] $others = @($drives | Where-Object { $_ -notin $named })

        if ($others.Count -gt 0) {
            $refused.Add(
                "roll $($roll.Id) on $($roll.Cluster) also runs $($others -join ', ')")
            continue
        }

        $picked.Add($roll)
    }

    [string] $asked = $Test -join ', '

    if ($refused.Count -gt 0) {
        Write-Error ("REFUSED. A run is stopped whole, and stopping these would stop " +
            "tests not named in -Test ${asked}: $($refused -join '; '). Name every " +
            'test it runs, or stop the whole run with -Cluster alone. Nothing was stopped.')
        return
    }

    if ($picked.Count -eq 0) {
        [string] $where = if ([string]::IsNullOrEmpty($Cluster)) { '' } else { " on $Cluster" }
        Write-Error "REFUSED. No roll$where runs a test matching $asked. $there"
        return
    }

    return $picked.ToArray()
}
