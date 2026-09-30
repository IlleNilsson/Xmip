#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Running a group of suites, and a third party's declared suite.

.DESCRIPTION
    Apart from Start-XmipTest.ps1 since 2026-09-22, when that file was 944 lines
    against the 400 the estate allows a file and the owner asked for the estate to
    be consolidated. Start-XmipTest chooses and refuses; what each kind of suite
    then does is here, except the estate's own Pester suite, which is
    Start-XmipEstateSuite.ps1 since 2026-09-25.

    Style: doc/governance/powershell-style.md
#>


# The parameters that mean something only to the Playground suite.
[string[]] $script:XmipPlaygroundOnly = @(
    'Cluster',
    'Stress', 'Rounds', 'Duration', 'TimeFactor'
    'Nodes', 'OnlineNodes', 'NodeCapability', 'LoadBytes', 'PassThru', 'Hidden'
)

function Resolve-XmipTestSuite {
    <#
        .SYNOPSIS
            The suites a name or pattern given to Start-XmipTest names, or
            nothing after refusing it in words.

        .DESCRIPTION
            Which suites there are is read, never declared at the parameter: a
            third party's is a file it dropped, and this session may have
            started before it existed. Whatever was typed, the suite says what
            it is called: a bare Playground resolves to the Playground and the
            record carries the canonical spelling, Core.Playground (ADR-0059,
            amendment 2026-09-20). Part of Start-XmipTest's body until
            2026-09-30.

        .PARAMETER Name
            What -Suite was given.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestSuite')]
    param(
        [Parameter(Mandatory)]
        [SupportsWildcards()]
        [string] $Name
    )

    [object[]] $known = @(Get-XmipTestSuite)
    [string] $refused = Get-XmipTestSuiteRefusal -Name $Name -Known $known

    if ($refused -ne '') {
        Write-Error $refused
        return
    }

    return Get-XmipNamedTestSuite -Name $Name -Known $known
}

function Start-XmipPesterSuite {
    <#
        .SYNOPSIS
            Starts the estate's Pester suite for Start-XmipTest, refusing a
            switch that belongs to the Playground alone.

        .DESCRIPTION
            Part of Start-XmipTest's body until 2026-09-30, when -Hidden took
            the room that file had left. -Caller is Start-XmipTest's own
            $PSCmdlet, so -WhatIf and -Confirm decide here as they did there.

        .PARAMETER Caller
            Start-XmipTest itself, for ShouldProcess.

        .PARAMETER Bound
            What Start-XmipTest was called with.

        .PARAMETER Suite
            The suite's canonical name.

        .PARAMETER Path
            As Start-XmipTest takes it.

        .PARAMETER Test
            As Start-XmipTest takes it.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet] $Caller,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound,

        [Parameter(Mandatory)]
        [string] $Suite,

        [Parameter()]
        [string] $Path,

        [Parameter()]
        [string[]] $Test = @()
    )

    [string[]] $foreign = @($Bound.Keys | Where-Object { $_ -in $script:XmipPlaygroundOnly })

    if ($foreign.Count -gt 0) {
        Write-Error ("-$($foreign -join ', -') belong to " +
            "$script:XmipPlaygroundSuite, not $Suite.")
        return
    }

    if (-not $Caller.ShouldProcess("the $Suite Pester suite", 'Start')) {
        return
    }

    return Start-XmipEstateSuite -Path $Path -Test $Test
}

function Start-XmipTestSuiteGroup {
    <#
        .SYNOPSIS
            Runs every suite a pattern matched, in the order they are listed,
            saying in words which are about to run and which did not start.

        .DESCRIPTION
            Each is started through Start-XmipTest itself, so a group run and
            a single run are the same run: the same refusals, the same
            records, the same -WhatIf. Two things differ, and only because a
            pattern chose the group rather than an operator naming one suite.

            A switch that belongs to the Playground alone is dropped for the
            estate's Pester suite rather than refused — -Suite * -Cluster C1
            is not a mistake about -Cluster; it is a roll on C1 with the
            estate's files beside it. A provider's command keeps everything,
            since only the provider knows what its command takes.

            One suite that will not start does not stop the others, which is
            the rule a malformed declaration already follows (ADR-0059): what
            another provider wrote may never stop Xmip's own tests. Each
            failure is said by name and again at the end.

        .PARAMETER Suite
            The suites matched, in the order Get-XmipTestSuite lists them.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object[]] $Suite,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [string[]] $names = @($Suite | ForEach-Object { $_.Name })
    Write-Host "Running $($names.Count) suites in order: $($names -join ', ')."

    [System.Collections.Generic.List[string]] $refused = @()

    foreach ($one in $Suite) {
        [hashtable] $forward = @{}

        foreach ($key in @($Bound.Keys)) {
            $forward[$key] = $Bound[$key]
        }

        $forward['Suite'] = $one.Name
        $forward['ErrorAction'] = 'Stop'

        if ($one.Kind -eq 'pester') {
            foreach ($only in $script:XmipPlaygroundOnly) {
                $forward.Remove($only)
            }
        }

        try {
            Start-XmipTest @forward
        }
        catch {
            $refused.Add($one.Name)
            Write-Host "FAILED $($one.Name) did not start: $($_.Exception.Message)"
        }
    }

    [string] $ran = $names -join ', '

    if ($refused.Count -eq 0) {
        Write-Host "OK $($names.Count) suites started: $ran."
        return
    }

    [string] $missing = $refused -join ', '
    Write-Host "FAILED $($refused.Count) of $($names.Count) did not start: $missing."
}


function Start-XmipProviderSuite {
    <#
        .SYNOPSIS
            Starts a suite a provider declared, through the command the
            declaration names, with everything -Suite was given beside it.

        .DESCRIPTION
            Xmip runs nothing of its own here. The declaration says which
            command starts the suite and that command is the provider's
            (ADR-0011: the provider slot states who stands behind it). A
            command this session does not have is REFUSED by name, with the
            declaration that named it, before anything runs.

            -Test is forwarded only when the operator named tests. Nothing
            named is the whole suite, for every suite and every provider, so
            the provider's command is called the way it would be called by
            hand for a full run.

        .PARAMETER Suite
            The suite, from Get-XmipTestSuite.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('Xmip.TestSuite')]
        [PSObject] $Suite,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    $command = Get-Command -Name $Suite.Command -ErrorAction SilentlyContinue

    if ($null -eq $command) {
        Write-Error ("REFUSED. $($Suite.Name) starts with $($Suite.Command), which this " +
            "session does not have. $($Suite.Source) declares it; import the module " +
            'that provides it, or correct the declaration.')
        return
    }

    [hashtable] $forward = @{}

    foreach ($given in @($Bound.Keys)) {
        if ($given -eq 'Suite') {
            continue
        }

        if ($given -eq 'Test' -and (Test-XmipWholeSuite -Test $Bound['Test'])) {
            continue
        }

        $forward[$given] = $Bound[$given]
    }

    if (-not $PSCmdlet.ShouldProcess($Suite.Name, 'Start')) {
        return
    }

    return & $command @forward
}
