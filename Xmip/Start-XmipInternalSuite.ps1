#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Starting a run of Core.Internal, the internal tests of the modules -Test
    names: detached, in a pwsh of its own, recorded as an estate run is.

.DESCRIPTION
    The internal tests are the code's own, cargo's, Pester's and .NET's,
    which every landing runs (ADR-0028, amendment 2026-11-23). Core.Estate is
    the root's Pester files; Core.Internal is the landing's own verification
    of the modules named (Test-XmipChangeTree -Alone): what their tests load,
    built first; each crate's format, its lints with every feature, its tests
    and lints with its default features and its tests with every feature;
    each module's .NET projects, extension shell and Event bindings. Not the
    root crate, the workspace's lints or the timing programs, which a landing
    adds for the change as a whole. It runs as Core.Estate runs, detached,
    its record and log under .local-work/estate, so Get-XmipTestStatus,
    Get-XmipTestResult and Stop-XmipTest read and stop it the same way, here
    or on a test computer (-ComputerName). Its whole suite is every module,
    so it is started by its name alone (the owner, 2026-11-23: "Do what you
    recommend").

    Style: doc/governance/powershell-style.md
#>


function Start-XmipInternalSuite {
    <#
        .SYNOPSIS
            Starts Core.Internal for Start-XmipTest and returns the run at
            once, running.

        .PARAMETER Caller
            Start-XmipTest itself, for ShouldProcess.

        .PARAMETER Bound
            What Start-XmipTest was called with.

        .PARAMETER Test
            The modules, by their folder from the estate's root as a landing
            names them, wildcards allowed; none for every module.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet] $Caller,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Test = @()
    )

    [string] $suite = $script:XmipInternalSuite
    [string] $refused = Get-XmipSuiteSwitchRefusal -Kind internal -Bound $Bound

    if ($refused -ne '') {
        Write-Error $refused
        return
    }

    $layout = Get-XmipSystemTestLayout
    [string[]] $known = @(Get-XmipInternalTest -RepositoryRoot $layout.Root)
    [string[]] $named = if (Test-XmipWholeSuite -Test $Test) { $known }
    else { @(Expand-XmipTestName -Test $Test -Known $known) }

    if (-not $Caller.ShouldProcess("$suite, $($named.Count) module(s)", 'Start')) {
        return
    }

    [string] $area = $layout.Estate
    New-Item -ItemType Directory -Path $area -Force | Out-Null
    Remove-XmipRunFinished -Run @(Get-XmipEstateRun -Path $area | Where-Object Suite -EQ $suite)

    [string] $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    [hashtable] $run = @{
        Record = Join-Path -Path $area -ChildPath "estate-$stamp.toml"
        Suite  = $suite
        Path   = $layout.Root
        Test   = $named
        Log    = Join-Path -Path $area -ChildPath "estate-$stamp.log"
    }

    $process = Start-XmipDetachedShell -Script (New-XmipInternalCommand @run) -Log $run.Log
    Write-XmipEstateStart @run -Kind internal -Id $process.Id -Started $process.StartTime

    Write-Host ("Started $suite ($($named -join ', ')) as pid $($process.Id), in its own " +
        "pwsh, detached. Log: $($run.Log). Get-XmipTestStatus says how it stands, " +
        "Get-XmipTestResult -Suite $suite what failed, and Stop-XmipTest -Id " +
        "$($process.Id) stops it.")

    return Get-XmipEstateRun -Path $area | Where-Object { $_.Id -eq $process.Id }
}


function Get-XmipInternalTest {
    <#
        .SYNOPSIS
            The modules Core.Internal knows, as a landing names them: the
            root crate, `.`; every member of the estate's one workspace, as
            the root's Cargo.toml lists it; and every module holding .NET
            projects and no crate of its own.

        .PARAMETER RepositoryRoot
            The estate's root.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    $manifest = Read-XmipToml -Path (Join-Path -Path $RepositoryRoot -ChildPath 'Cargo.toml')
    $workspace = Get-TomlValue -Node $manifest -Name 'workspace'
    [string[]] $member = @(Get-TomlValue -Node $workspace -Name 'members' -Default @())

    [string[]] $dotnet = @(
        Get-XmipSubmodule -Root $RepositoryRoot | ForEach-Object { $_.Path } | Where-Object {
            [string] $folder = Join-Path -Path $RepositoryRoot -ChildPath $_
            -not (Test-Path -LiteralPath (Join-Path $folder 'Cargo.toml')) -and
                $null -ne (Find-XmipFile -Path $folder -Filter '*.csproj' | Select-Object -First 1)
        }
    )

    return @(@('.') + $member + $dotnet | Sort-Object -Unique)
}


function New-XmipInternalCommand {
    <#
        .SYNOPSIS
            The script a detached run of Core.Internal executes in its own
            pwsh: the landing's verification of the modules named, then its
            verdict written (Complete-XmipInternalRun).

        .DESCRIPTION
            Every value is written into it as a single-quoted literal, as an
            estate run's is (New-XmipEstateCommand).

        .PARAMETER Path
            The estate's root.

        .PARAMETER Test
            The modules named.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Record,

        [Parameter(Mandatory)]
        [string] $Suite,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string[]] $Test,

        [Parameter(Mandatory)]
        [string] $Log
    )

    [string] $manifest = ConvertTo-XmipLiteral -Text (Join-Path $PSScriptRoot 'Xmip.psd1')
    [string] $modules = '@(' + (@($Test | ForEach-Object {
                ConvertTo-XmipLiteral -Text $_ }) -join ', ') + ')'

    return @(
        '$ErrorActionPreference = ''Stop'''
        "`$xmip = Import-Module -Name $manifest -PassThru"
        "`$run = @{ Record = $(ConvertTo-XmipLiteral -Text $Record)"
        "    Suite = $(ConvertTo-XmipLiteral -Text $Suite)"
        "    Path = $(ConvertTo-XmipLiteral -Text $Path)"
        "    Test = $modules; Log = $(ConvertTo-XmipLiteral -Text $Log) }"
        '$started = Get-Date'
        '$verdict = $null'
        '$fault = '''''
        'try {'
        '    $verdict = & $xmip {'
        '        param($Run)'
        '        Test-XmipChangeTree -RepositoryRoot $Run.Path -Ordered $Run.Test -Alone'
        '    } $run'
        '}'
        'catch { $fault = "$_" }'
        '& $xmip {'
        '    param($Run, $Verdict, $Fault, $Started)'
        '    Complete-XmipInternalRun @Run -Verdict $Verdict -Fault $Fault -Started $Started'
        '} $run $verdict $fault $started'
    ) -join [Environment]::NewLine
}


function Complete-XmipInternalRun {
    <#
        .SYNOPSIS
            Writes a finished run of Core.Internal's verdict into its record:
            OK where every module named verified, FAILED naming the module or
            the part where the verification stopped.

        .PARAMETER Verdict
            What Test-XmipChangeTree returned: Verified, Skipped and Failed;
            $null where it threw.

        .PARAMETER Fault
            What it threw, or empty.

        .PARAMETER Started
            When the verification began.
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

        [Parameter(Mandatory)]
        [string[]] $Test,

        [Parameter(Mandatory)]
        [string] $Log,

        [Parameter()]
        [AllowNull()]
        [object] $Verdict,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Fault = '',

        [Parameter(Mandatory)]
        [datetime] $Started
    )

    [string] $stopped = if ($null -ne $Verdict) { [string] $Verdict.Failed } else { '' }
    [string] $parts = (Get-XmipEstateLayout -Root $Path).Landing
    [object[]] $failure = @(
        if ($stopped -ne '') {
            [ordered]@{
                file    = $stopped
                path    = $stopped
                message = ("$stopped did not verify; the log says why: $Log, and a part " +
                    "that failed, its own log under $parts.")
            }
        }
        elseif ($null -eq $Verdict) {
            if ($Fault -eq '') {
                $Fault = 'Test-XmipChangeTree returned nothing.'
            }

            [ordered]@{ file = ''; path = ''; message = $Fault }
        }
    )

    [hashtable] $counted = @{
        State   = if ($failure.Count -eq 0) { 'OK' } else { 'FAILED' }
        Passed  = if ($null -ne $Verdict) { @($Verdict.Verified).Count } else { 0 }
        Failed  = $failure.Count
        Skipped = if ($null -ne $Verdict) { @($Verdict.Skipped).Count } else { 0 }
        Seconds = ((Get-Date) - $Started).TotalSeconds
        Fault   = $Fault
        Failure = $failure
    }
    [hashtable] $run = @{ Record = $Record; Suite = $Suite; Path = $Path; Test = $Test; Log = $Log }

    Write-XmipRunVerdict @run @counted -Kind internal
}
