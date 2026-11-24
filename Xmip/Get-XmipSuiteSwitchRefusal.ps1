#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Which of Start-XmipTest's switches each of Xmip's own suites takes, and
    the words refusing the rest.

.DESCRIPTION
    One table for the three of them since 2026-11-10, when Core.Demo, the
    demo readiness check, joined Core.System and Core.Estate with a
    switch of its own, -Tester (ADR-0028, amendment 2026-11-10). Until then
    a list of the System Tests' switches refused them on the estate's suite and
    nothing refused anything on the System Tests. Start-XmipTest refuses through
    Get-XmipSuiteSwitchRefusal for the one suite named, and a group drops
    through Get-XmipSuiteSwitchForeign for each suite a pattern chose.

    Style: doc/governance/powershell-style.md
#>


# Which of Start-XmipTest's switches each kind of Xmip's own suites takes
# beside -Suite: roll is Core.System and Core.Systems, pester Core.Estate,
# internal Core.Internal, demo Core.Demo. -ComputerName is the internal
# tests' alone, Core.Estate's and Core.Internal's: they run on another
# computer (Start-XmipTestOnComputer).
# A provider's command is handed everything (Start-XmipProviderSuite). A
# switch belongs to the first kind listed that takes it.
[System.Collections.Specialized.OrderedDictionary] $script:XmipSuiteSwitch = [ordered]@{
    roll     = @(
        'Stress', 'Test', 'Rounds', 'Duration', 'TimeFactor', 'Nodes', 'NodeRole', 'NodeCapability'
        'Cluster', 'Certificate', 'LoadBytes', 'Path', 'PassThru', 'Hidden'
    )
    pester   = @('Test', 'Path', 'ComputerName')
    internal = @('Test', 'ComputerName')
    demo     = @('Cluster', 'Stress', 'Hidden', 'Tester')
}

function Get-XmipSuiteSwitchForeign {
    <#
        .SYNOPSIS
            The switches given that a kind of Xmip's own suites does not take,
            -Suite and PowerShell's common parameters never among them. Pure.

        .PARAMETER Kind
            roll, pester, internal or demo.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('roll', 'pester', 'internal', 'demo')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [string[]] $common = @(
        [System.Management.Automation.Cmdlet]::CommonParameters
        [System.Management.Automation.Cmdlet]::OptionalCommonParameters
        'Suite'
    )

    return [string[]] @(
        $Bound.Keys | Where-Object {
            $_ -notin $common -and $_ -notin $script:XmipSuiteSwitch[$Kind]
        }
    )
}

function Get-XmipSuiteSwitchRefusal {
    <#
        .SYNOPSIS
            Why a suite of Xmip's own refuses the switches it was given, or
            the empty string when it takes them all. Pure.

        .DESCRIPTION
            Each switch is said with the suite it belongs to: "-Stress belong
            to Core.System and Core.Systems, not Core.Estate." Refused before anything
            starts, as every refusal of Start-XmipTest is (ADR-0055 clause 2).

        .PARAMETER Kind
            roll, pester, internal or demo.

        .PARAMETER Bound
            What Start-XmipTest was called with.

        .PARAMETER Chosen
            The suite chosen, as the refusal names it; omitted, the kind's.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('roll', 'pester', 'internal', 'demo')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound,

        [Parameter()]
        [string] $Chosen = ''
    )

    [hashtable] $suite = @{
        roll     = "$script:XmipSystemTestSuite and $script:XmipSystemsTestSuite"
        pester   = "$script:XmipEstateSuite and $script:XmipInternalSuite"
        internal = $script:XmipInternalSuite
        demo     = $script:XmipDemoSuite
    }
    [string] $not = if ($Chosen -ne '') { $Chosen } else { $suite[$Kind] }
    [string[]] $foreign = @(Get-XmipSuiteSwitchForeign -Kind $Kind -Bound $Bound)
    [string[]] $said = @(
        foreach ($owner in @($script:XmipSuiteSwitch.Keys)) {
            [string[]] $owned = @(
                $foreign | Where-Object { $_ -in $script:XmipSuiteSwitch[$owner] }
            )
            $foreign = @($foreign | Where-Object { $_ -notin $owned })

            if ($owned.Count -gt 0) {
                "-$($owned -join ', -') belong to $($suite[$owner]), not $not."
            }
        }
    )

    if ($said.Count -eq 0) {
        return ''
    }

    return "REFUSED. $($said -join ' ')"
}
