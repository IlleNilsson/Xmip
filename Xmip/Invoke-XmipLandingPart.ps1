#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

<#
.SYNOPSIS
    The landing's independent parts side by side: the Rust workspace, the
    .NET projects and the estate's Pester suite, each in a pwsh of its own,
    with its share of the machine and a log of its own.

.DESCRIPTION
    The owner, 2026-11-20: "Still, the time it takes is not acceptable."
    Until then the landing verified module after module, then the root
    crate, then `test/`, then the .NET projects, one after another, though
    none reads what another writes: each starts from what the landing built
    before them, the runtime's library and the test module's. Side by side,
    the landing takes as long as its longest part.

    Each part runs in a job, a pwsh of its own, so its working folder and
    environment are its own; XMIP_TOOL_SHARE tells Invoke-XmipTool its share
    of the machine's twelve (Get-XmipToolShare). Its lines go to
    `.local-work/landing/part-<name>.log`. The first part to fail ends the
    others, every process beneath them with them, and is named with what
    failed in it, each crate or project and test, and the lines that say why;
    for Core.Internal every part runs to its end (-Whole). The timing
    programs run after, alone.

    Style: doc/governance/powershell-style.md
#>


function Invoke-XmipLandingPart {
    <#
        .SYNOPSIS
            Runs the parts side by side and says, for each, whether it passed,
            how long it took, its log and what failed in it (Failure, each
            Xmip.PartFailure, the part's own last lines where it named none).

        .PARAMETER Part
            Each a hashtable: Name, Command (a function of this module),
            Argument (its parameters) and Environment (variables the part
            sees in place of this session's). A command passes when it
            returns nothing or $true; $false, a string naming what failed or
            an Xmip.PartFailure (New-XmipPartFailure) fails it.

        .PARAMETER Whole
            Every part runs to its end, one's failure stopping no other, for
            Core.Internal, which names every failure; a landing ends the
            rest at the first.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable[]] $Part,

        [Parameter()]
        [switch] $Whole
    )

    if ($Part.Count -eq 0) {
        return
    }

    [string] $manifest = Join-Path -Path $PSScriptRoot -ChildPath 'Xmip.psd1'
    [string] $folder = (Get-XmipEstateLayout -Root $RepositoryRoot).Landing
    $null = New-Item -ItemType Directory -Path $folder -Force
    [hashtable] $share = Get-XmipToolShare -Part @($Part | ForEach-Object { $_.Name })

    # In the job: its share before the module reads it, its lines to its log,
    # and its process written beside the log so a failure elsewhere can end it.
    [scriptblock] $run = {
        param([string] $Manifest, [int] $Share, [string] $Command, [hashtable] $Argument,
            [hashtable] $Environment, [string] $Log)

        $env:XMIP_TOOL_SHARE = "$Share"

        foreach ($name in $Environment.Keys) {
            Set-Item -Path "env:$name" -Value $Environment[$name]
        }

        Set-Content -LiteralPath "$Log.pid" -Value $PID
        $writer = [IO.StreamWriter]::new($Log, $true)
        $writer.AutoFlush = $true

        try {
            $module = Import-Module -Name $Manifest -PassThru -Force 3>$null
            & $module {
                param($Command, $Argument)
                & $Command @Argument
            } $Command $Argument *>&1 | ForEach-Object {
                if ($_ -is [Management.Automation.InformationRecord] -or
                    $_ -is [Management.Automation.ErrorRecord] -or
                    $_ -is [Management.Automation.WarningRecord]) {
                    $writer.WriteLine("$_")
                }
                else {
                    $_
                }
            }
        }
        finally {
            $writer.Dispose()
        }
    }

    [datetime] $started = Get-Date
    [List[object]] $running = [List[object]]::new()

    foreach ($one in $Part) {
        [string] $leaf = "part-$($one.Name.ToLowerInvariant()).log"
        [string] $log = Join-Path -Path $folder -ChildPath $leaf
        Set-Content -LiteralPath $log -Value $null
        Write-Host "   $($one.Name): started, $($share[$one.Name]) threads; its lines: $log"
        [hashtable] $environment = @{}

        if ($one.ContainsKey('Environment')) {
            $environment = $one.Environment
        }

        [object[]] $given = @($manifest, $share[$one.Name], $one.Command, $one.Argument,
            $environment,
            $log)
        $job = Start-Job -Name $one.Name -ScriptBlock $run -ArgumentList $given
        $running.Add([pscustomobject]@{ Job = $job; Name = $one.Name; Log = $log })
    }

    [List[pscustomobject]] $verdicts = [List[pscustomobject]]::new()

    while ($running.Count -gt 0) {
        $done = Wait-Job -Job @($running.Job) -Any -Timeout 60

        if (-not $done) {
            [int] $minutes = ((Get-Date) - $started).TotalMinutes
            Write-Host "   still running after $minutes min: $(@($running.Name) -join ', ')"
            continue
        }

        $entry = $running | Where-Object { $_.Job.Id -eq $done.Id } | Select-Object -First 1
        [object[]] $said = @(Receive-Job -Job $done -ErrorAction SilentlyContinue 2>&1)
        [object[]] $failure = @(ConvertTo-XmipPartFailure -Said $said)
        [bool] $passed = $done.State -eq 'Completed' -and $failure.Count -eq 0 -and
            @($said | Where-Object { $_ -is [bool] -and -not $_ }).Count -eq 0
        Remove-Job -Job $done -Force
        Remove-Item -LiteralPath "$($entry.Log).pid" -ErrorAction SilentlyContinue
        $running.Remove($entry) | Out-Null

        [timespan] $took = (Get-Date) - $started
        [string[]] $telling = @(
            if (-not $passed) {
                Get-Content -LiteralPath $entry.Log -ErrorAction SilentlyContinue |
                    Select-String -Pattern $script:XmipToolTelling |
                    Select-Object -Last $script:XmipToolTold | ForEach-Object { $_.Line }
            }
        )

        # A part that failed and named nothing is named by its own last lines.
        if (-not $passed -and $failure.Count -eq 0) {
            $failure = @(New-XmipPartFailure -Test $entry.Name -Message (
                    "$($entry.Name) failed: $($telling -join ' | ')"))
        }

        $verdicts.Add([pscustomobject]@{
                Name = $entry.Name; Passed = $passed; Took = $took; Log = $entry.Log
                Failure = $failure
            })

        if ($passed) {
            [string] $ok = 'OK       {0}, {1:N1} min' -f $entry.Name, $took.TotalMinutes
            Write-Host $ok -ForegroundColor Green
            continue
        }

        [string] $headline = 'FAILED   {0}, {1:N1} min' -f $entry.Name, $took.TotalMinutes
        Write-Host $headline -ForegroundColor Red
        $failure | ForEach-Object { Write-Host "         $($_.Module) $($_.Test): $($_.Message)" }
        $telling | ForEach-Object { Write-Host "         $_" }

        if ($Whole) {
            continue
        }

        # The first failure ends the rest: nothing more is worth waiting for.
        foreach ($other in $running) {
            Stop-XmipLandingPart -Log $other.Log
            Stop-Job -Job $other.Job
            Remove-Job -Job $other.Job -Force
            Remove-Item -LiteralPath "$($other.Log).pid" -ErrorAction SilentlyContinue
            $verdicts.Add([pscustomobject]@{
                    Name = $other.Name; Passed = $false; Took = $took; Log = $other.Log
                    Failure = @()
                })
            [string] $stopped = "STOPPED  $($other.Name), after $($entry.Name) failed"
            Write-Host $stopped -ForegroundColor Yellow
        }

        $running.Clear()
    }

    $verdicts
}


function New-XmipPartFailure {
    <#
        .SYNOPSIS
            One failure a part of the landing names, Xmip.PartFailure:
            Module, the crate's or module's folder, empty where it is not
            known; Test, the test, the target or the step; Message, the words
            that say why.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.PartFailure')]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Module = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Test = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Message = ''
    )

    return [pscustomobject]@{
        PSTypeName = 'Xmip.PartFailure'
        Module     = $Module
        Test       = $Test
        Message    = $Message
    }
}


function ConvertTo-XmipPartFailure {
    <#
        .SYNOPSIS
            The failures among what a part's command returned: each
            Xmip.PartFailure, as it crossed from the part's pwsh, and each
            string naming what failed.

        .PARAMETER Said
            What the part's job returned.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.PartFailure')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Said
    )

    foreach ($one in $Said) {
        if ($one -is [string] -and $one) {
            New-XmipPartFailure -Module $one
        }
        elseif ($null -ne $one -and $one -isnot [bool] -and $one.PSObject.Properties['Module']) {
            New-XmipPartFailure -Module $one.Module -Test $one.Test -Message $one.Message
        }
    }
}


function Stop-XmipLandingPart {
    <#
        .SYNOPSIS
            Ends a part's pwsh and every process beneath it: cargo, dotnet,
            the test programs and whatever they started.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Log
    )

    [string] $written = Get-Content -LiteralPath "$Log.pid" -ErrorAction SilentlyContinue

    if (-not $written) {
        return
    }

    $process = Get-Process -Id ([int] $written) -ErrorAction SilentlyContinue

    [string] $named = "$($process.Name) $($process.Id)"

    if ($process -and $PSCmdlet.ShouldProcess($named, 'Stop with its tree')) {
        $process.Kill($true)
    }
}
