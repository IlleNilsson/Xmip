#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Starting a suite of the internal tests on a test computer: the estate sent
    there, then that computer's own Start-XmipTest.

.DESCRIPTION
    Start-XmipTest -ComputerName <name> runs Core.Estate or Core.Internal on
    the computer <name>.toml names (Read-XmipTestComputer), detached there as
    it runs detached here; Get-XmipTestStatus, Get-XmipTestResult and
    Stop-XmipTest take the same -ComputerName. The Linux checks ran through
    two bash scripts outside the estate until 2026-11-23 (the owner,
    2026-11-23: "Do what you recommend").

    Style: doc/governance/powershell-style.md
#>


function Start-XmipTestOnComputer {
    <#
        .SYNOPSIS
            Starts the suite Start-XmipTest chose on the computer
            -ComputerName names and returns its run, as that computer's
            estate lists it, ComputerName saying where.

        .DESCRIPTION
            Refused before anything is sent: a suite that does not run there,
            by the switch table every suite of Xmip's own is refused by
            (Get-XmipSuiteSwitchRefusal); -Path, a folder of this computer;
            and a computer whose file is not there. -WhatIf sends nothing.

        .PARAMETER Chosen
            The suite, from Get-XmipTestSuite.

        .PARAMETER Caller
            Start-XmipTest itself, for ShouldProcess.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('Xmip.TestSuite')]
        [PSObject] $Chosen,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet] $Caller,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [string] $name = $Bound['ComputerName']
    [string] $refused = Get-XmipComputerSuiteRefusal -Chosen $Chosen -Bound $Bound

    if ($refused -ne '') {
        Write-Error $refused
        return
    }

    $computer = Read-XmipTestComputer -Name $name

    if (-not $Caller.ShouldProcess("$($Chosen.Name) on $name", 'Start')) {
        return
    }

    Send-XmipTestComputerEstate -Computer $computer

    [hashtable] $given = @{ Suite = $Chosen.Name }

    if ($Bound.ContainsKey('Test')) {
        $given.Test = [string[]] @($Bound['Test'])
    }

    [hashtable] $asked = @{
        Computer = $computer; Command = 'Start-XmipTest'; Parameter = $given; Start = $true
    }
    [object[]] $started = @(
        Invoke-XmipTestComputer @asked | ConvertFrom-XmipTestComputerStatus -ComputerName $name
    )

    foreach ($run in $started) {
        Write-Host ("Started on ${name}: Get-XmipTestStatus -ComputerName $name says how it " +
            "stands, Get-XmipTestResult -Suite $($run.Suite) -ComputerName $name what " +
            "failed, and Stop-XmipTest -ComputerName $name -Id $($run.Id) stops it.")
    }

    return $started
}


function Get-XmipComputerSuiteRefusal {
    <#
        .SYNOPSIS
            Why a suite is not started on a test computer, or the empty
            string when it is. Pure.

        .PARAMETER Chosen
            The suite, from Get-XmipTestSuite.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Chosen,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    if ($Chosen.Kind -eq 'command') {
        return ("REFUSED. $($Chosen.Name) is a provider's suite, started here by its own " +
            "command; -ComputerName belongs to $script:XmipEstateSuite and " +
            "$script:XmipInternalSuite.")
    }

    [string] $refused = Get-XmipSuiteSwitchRefusal -Kind $Chosen.Kind -Bound $Bound -Chosen (
        $Chosen.Name)

    if ($refused -ne '') {
        return $refused
    }

    if ($Bound.ContainsKey('Path')) {
        return ("REFUSED. -Path names a folder of this computer; on " +
            "$($Bound['ComputerName']), $($Chosen.Name) runs the copy of the estate sent there.")
    }

    # A pattern matching none of the tests sent is refused before the send,
    # as the suite there would refuse it after.
    if (-not (Test-XmipWholeSuite -Test $Bound['Test'])) {
        try {
            [string[]] $known = @(Get-XmipTestChoice -Suite $Chosen.Name)
            $null = Expand-XmipTestName -Test $Bound['Test'] -Known $known
        }
        catch {
            return $_.Exception.Message
        }
    }

    return ''
}


function Install-XmipTestComputerLibrary {
    <#
        .SYNOPSIS
            Run on the test computer, in the copy of the estate there, before
            a suite starts: the RocksDB library every build under the root
            links, compiled once as any clone compiles it
            (Install-XmipNativeLibrary), and said to be there after; then the
            runtime library the suite's rules are read through, built from
            the copy as it now is.

        .DESCRIPTION
            The copy is a clone this module keeps there, and nobody else
            prepares it: until 2026-11-23 the Linux checks linked another
            tree's library into theirs, and a copy of its own failed
            NativeLibrary.Test.ps1. The build slot the start holds is held
            for the compile too.

            Every send changes the copy's sources, and a runtime library built
            before it was used as it was, since one was there: on 2026-11-25
            a Core.Estate run read the morning's, without that day's
            xmip_publication_instances_v1, and 391 tests failed before testing
            anything (open problem 208). It is built again before every start,
            cargo deciding whether anything changed, as a landing builds it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()

    [string] $path = (Get-XmipEstateLayout).Prerequisite
    [hashtable] $source = @{
        Manifest     = Read-XmipToml -Path $path
        ManifestPath = $path
        Role         = @('build')
        Install      = $true
        Caller       = $PSCmdlet
    }

    $null = Install-XmipNativeLibrary @source

    if ($PSCmdlet.ShouldProcess('the runtime library', 'Build from the copy')) {
        $null = Build-XmipRuntimeLibrary -Root (Get-XmipRepositoryRoot) -Fresh
    }
}
