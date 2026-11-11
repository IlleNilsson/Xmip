#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Which of Start-XmipTest's switches each of Xmip's own suites takes, and
    the words refusing the rest.

.DESCRIPTION
    One table for the three of them since 2026-11-10, when Core.Demo, the
    demo readiness check, joined Core.Essentials and Core.Estate with a
    switch of its own, -Tester (ADR-0028, amendment 2026-11-10). Until then
    a list of the Essentials' switches refused them on the estate's suite and
    nothing refused anything on the Essentials. Start-XmipTest refuses through
    Get-XmipSuiteSwitchRefusal for the one suite named, and a group drops
    through Get-XmipSuiteSwitchForeign for each suite a pattern chose.

    Style: doc/governance/powershell-style.md
#>


# Which of Start-XmipTest's switches each kind of Xmip's own suites takes
# beside -Suite: roll is Core.Essentials, pester Core.Estate, demo Core.Demo.
# A provider's command is handed everything (Start-XmipProviderSuite). A
# switch belongs to the first kind listed that takes it.
[System.Collections.Specialized.OrderedDictionary] $script:XmipSuiteSwitch = [ordered]@{
    roll   = @(
        'Stress', 'Test', 'Rounds', 'Duration', 'TimeFactor', 'Nodes', 'NodeRole', 'OnlineNodes'
        'Cluster', 'Certificate', 'LoadBytes', 'Path', 'PassThru', 'Hidden'
    )
    pester = @('Test', 'Path')
    demo   = @('Cluster', 'Stress', 'Hidden', 'Tester')
}

function Get-XmipSuiteSwitchForeign {
    <#
        .SYNOPSIS
            The switches given that a kind of Xmip's own suites does not take,
            -Suite and PowerShell's common parameters never among them. Pure.

        .PARAMETER Kind
            roll, pester or demo.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('roll', 'pester', 'demo')]
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
            to Core.Essentials, not Core.Estate." Refused before anything
            starts, as every refusal of Start-XmipTest is (ADR-0055 clause 2).

        .PARAMETER Kind
            roll, pester or demo.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('roll', 'pester', 'demo')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [hashtable] $suite = @{
        roll   = $script:XmipEssentialsSuite
        pester = $script:XmipEstateSuite
        demo   = $script:XmipDemoSuite
    }
    [string[]] $foreign = @(Get-XmipSuiteSwitchForeign -Kind $Kind -Bound $Bound)
    [string[]] $said = @(
        foreach ($owner in @($script:XmipSuiteSwitch.Keys)) {
            [string[]] $owned = @(
                $foreign | Where-Object { $_ -in $script:XmipSuiteSwitch[$owner] }
            )
            $foreign = @($foreign | Where-Object { $_ -notin $owned })

            if ($owned.Count -gt 0) {
                "-$($owned -join ', -') belong to $($suite[$owner]), not $($suite[$Kind])."
            }
        }
    )

    if ($said.Count -eq 0) {
        return ''
    }

    return "REFUSED. $($said -join ' ')"
}
