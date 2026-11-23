#requires -Version 7.7.0

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    What a run of the estate's Pester suite writes when Pester returns: its verdict.

.DESCRIPTION
    Called by the run itself, in its own pwsh (Start-XmipEstateSuite), never by
    the console that started it. The record it writes is read by
    Get-XmipEstateRun, and written by Write-XmipRunVerdict, which a run of the
    internal tests of named modules writes its verdict with too.

    Style: doc/governance/powershell-style.md
#>


function Complete-XmipEstateRun {
    <#
        .SYNOPSIS
            Writes a finished run's verdict into its record: the counts, the
            duration and every failure's path and message.

        .DESCRIPTION
            Called by the run itself, in its own pwsh, once Invoke-Pester has
            returned — never by the console that started it. The whole record
            is written from what the run knows, so nothing Start wrote needs
            reading back and the two never race over one file.

        .PARAMETER Record
            The record's path.

        .PARAMETER Suite
            The suite's canonical name.

        .PARAMETER Path
            The directory of Pester tests the run was given.

        .PARAMETER Test
            The test files named, without the suffix; none for the whole suite.

        .PARAMETER Log
            The run's log.

        .PARAMETER Result
            What Invoke-Pester returned; $null when it threw.

        .PARAMETER Fault
            What Invoke-Pester threw, or empty.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Record,

        [Parameter(Mandatory)]
        [string] $Suite,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Test = @(),

        [Parameter(Mandatory)]
        [string] $Log,

        [Parameter()]
        [AllowNull()]
        [object] $Result,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Fault = ''
    )

    [bool] $passed = $null -ne $Result -and $Result.Result -eq 'Passed' -and $Fault -eq ''

    if ($null -eq $Result -and $Fault -eq '') {
        $Fault = 'Invoke-Pester returned nothing.'
    }

    [hashtable] $verdict = @{
        State   = if ($passed) { 'OK' } else { 'FAILED' }
        Passed  = if ($null -ne $Result) { [int] $Result.PassedCount } else { 0 }
        Failed  = if ($null -ne $Result) { [int] $Result.FailedCount } else { 0 }
        Skipped = if ($null -ne $Result) { [int] $Result.SkippedCount } else { 0 }
        Seconds = if ($null -ne $Result) { $Result.Duration.TotalSeconds } else { 0 }
        Fault   = $Fault
        Failure = @(Get-XmipEstateFailure -Result $Result)
    }
    [hashtable] $run = @{ Record = $Record; Suite = $Suite; Path = $Path; Test = $Test; Log = $Log }

    Write-XmipRunVerdict @run @verdict -Kind pester
}


function Write-XmipRunVerdict {
    <#
        .SYNOPSIS
            Writes a detached run's verdict into its record, whole: what was
            started, the state in words, the counts, the duration and every
            failure. The one writer of a verdict, for the estate's Pester
            suite (Complete-XmipEstateRun) and the internal tests of named
            modules (Complete-XmipInternalRun), each run in its own pwsh.

        .PARAMETER Kind
            pester or internal, as Get-XmipTestStatus lists the run.

        .PARAMETER Failure
            Each failure as a table: file, path and message.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Record,

        [Parameter(Mandatory)]
        [string] $Suite,

        [Parameter(Mandatory)]
        [ValidateSet('pester', 'internal')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Test = @(),

        [Parameter(Mandatory)]
        [string] $Log,

        [Parameter(Mandatory)]
        [ValidateSet('OK', 'FAILED')]
        [string] $State,

        [Parameter()]
        [int] $Passed = 0,

        [Parameter()]
        [int] $Failed = 0,

        [Parameter()]
        [int] $Skipped = 0,

        [Parameter()]
        [double] $Seconds = 0,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Fault = '',

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Failure = @()
    )

    $written = [ordered]@{
        suite      = $Suite
        kind       = $Kind
        pid        = $PID
        started    = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
        path       = $Path
        tests      = @($Test)
        log        = $Log
        finished   = [datetime]::UtcNow.ToString('o')
        state      = $State
        passed     = $Passed
        failed     = $Failed
        skipped    = $Skipped
        duration_s = [math]::Round($Seconds, 1)
        fault      = $Fault
        failures   = @($Failure)
    }

    Write-XmipToml -Path $Record -Value $written
}


function Get-XmipEstateFailure {
    <#
        .SYNOPSIS
            Every failure a Pester run holds, as the tables a record keeps:
            the file, the path Pester names it by, and the first message.

        .DESCRIPTION
            A failed test, and also a file or a block that failed around its
            tests — a BeforeAll that threw, a file that would not load — since
            those fail a run while no single test says so.

        .PARAMETER Result
            What Invoke-Pester returned, or $null.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Result
    )

    if ($null -eq $Result) {
        return
    }

    [object[]] $failed = @(
        $Result.Failed
        $Result.FailedBlocks
        $Result.FailedContainers
    )

    foreach ($one in $failed) {
        if ($null -eq $one) {
            continue
        }

        [string] $where = Get-XmipEstateFailureFile -Failure $one
        [object] $first = @($one.ErrorRecord) | Select-Object -First 1
        [string] $said = if ($null -ne $first) { $first.Exception.Message } else { '' }
        [string] $named = if ($one.PSObject.Properties['ExpandedPath']) {
            $one.ExpandedPath
        }
        else {
            [System.IO.Path]::GetFileName($where)
        }

        [ordered]@{
            file    = [System.IO.Path]::GetFileName($where) -replace '\.Test\.ps1$', ''
            path    = $named
            message = $said
        }
    }
}


function Get-XmipEstateFailureFile {
    <#
        .SYNOPSIS
            The test file a failed test, block or container came from.

        .PARAMETER Failure
            One of Pester's Failed, FailedBlocks or FailedContainers.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Failure
    )

    if ($Failure.PSObject.Properties['ScriptBlock'] -and $null -ne $Failure.ScriptBlock) {
        return [string] $Failure.ScriptBlock.File
    }

    if ($Failure.PSObject.Properties['Item']) {
        return [string] $Failure.Item
    }

    return ''
}


