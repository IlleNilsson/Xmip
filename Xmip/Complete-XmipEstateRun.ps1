#requires -Version 7.6.5

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    What a run of the estate's Pester suite writes when Pester returns: its verdict.

.DESCRIPTION
    Called by the run itself, in its own pwsh (Start-XmipEstateSuite), never by
    the console that started it. The record it writes is read by
    Get-XmipEstateRun.

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

    [double] $seconds = 0

    if ($null -ne $Result) {
        $seconds = [math]::Round($Result.Duration.TotalSeconds, 1)
    }

    $written = [ordered]@{
        suite      = $Suite
        pid        = $PID
        started    = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
        path       = $Path
        tests      = @($Test)
        log        = $Log
        finished   = [datetime]::UtcNow.ToString('o')
        state      = if ($passed) { 'OK' } else { 'FAILED' }
        passed     = if ($null -ne $Result) { [int] $Result.PassedCount } else { 0 }
        failed     = if ($null -ne $Result) { [int] $Result.FailedCount } else { 0 }
        skipped    = if ($null -ne $Result) { [int] $Result.SkippedCount } else { 0 }
        duration_s = $seconds
        fault      = $Fault
        failures   = @(Get-XmipEstateFailure -Result $Result)
    }

    Import-Module PSToml -ErrorAction Stop
    ConvertTo-Toml -InputObject $written -Depth 4 |
        Set-Content -LiteralPath $Record -Encoding utf8
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


