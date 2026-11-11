#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    One part of a demo readiness check's run: made, said in words, tried and
    added to the run.

.DESCRIPTION
    A part is OK, FAILED or SKIPPED, with the reason in words (ADR-0028,
    amendment 2026-11-10; CONTRIBUTING.md: outcomes in words, never color
    alone). The run says each as it ends, its record keeps each, and
    Get-XmipTestResult -Suite Core.Demo returns each in these same words.
    Trying a part and adding it to the run were in Test-XmipDemoReady.ps1
    until that file passed 400 lines, the same day.

    Style: doc/governance/powershell-style.md
#>


function New-XmipDemoPart {
    <#
        .SYNOPSIS
            One part's verdict: its name, OK, FAILED or SKIPPED, and why.

        .PARAMETER Name
            roll, web, desktop, extension or stop.

        .PARAMETER State
            OK, FAILED or SKIPPED.

        .PARAMETER Reason
            What the part found, in words.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.DemoPart')]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('OK', 'FAILED', 'SKIPPED')]
        [string] $State,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Reason
    )

    return [pscustomobject]@{
        PSTypeName = 'Xmip.DemoPart'
        Name       = $Name
        State      = $State
        Reason     = $Reason
    }
}


function Format-XmipDemoPart {
    <#
        .SYNOPSIS
            A part in words, its state first: "FAILED web: <why>".

        .PARAMETER Part
            The part, from New-XmipDemoPart.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Part
    )

    return "$($Part.State) $($Part.Name): $($Part.Reason)"
}


function Test-XmipDemoPart {
    <#
        .SYNOPSIS
            Runs one part's check and adds its verdict to the run: OK with
            what the check returned, FAILED with what it threw.

        .PARAMETER Run
            The run, from New-XmipDemoState.

        .PARAMETER Name
            The part.

        .PARAMETER Check
            What tries it: returns the reason it is OK, or throws why not.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.DemoPart')]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Run,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [scriptblock] $Check
    )

    $Run['doing'] = $Name
    Write-XmipDemoRecord -Run $Run
    Write-Host "== $Name"

    $part = try {
        New-XmipDemoPart -Name $Name -State 'OK' -Reason ([string] (& $Check))
    }
    catch {
        New-XmipDemoPart -Name $Name -State 'FAILED' -Reason $_.Exception.Message
    }

    Add-XmipDemoPart -Run $Run -Part $part

    return $part
}


function Add-XmipDemoPart {
    <#
        .SYNOPSIS
            Adds a part's verdict to the run: said in words, audited and
            written into the record.

        .PARAMETER Run
            The run, from New-XmipDemoState.

        .PARAMETER Part
            The part, from New-XmipDemoPart.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Run,

        [Parameter(Mandatory)]
        [PSObject] $Part
    )

    [hashtable] $severity = @{ OK = 'Information'; SKIPPED = 'Warning'; FAILED = 'Error' }
    [string] $line = Format-XmipDemoPart -Part $Part
    $Run['parts'].Add($Part)
    Write-Host $line

    [hashtable] $audited = @{
        Action   = 'Test-XmipDemoReady'
        Severity = $severity[$Part.State]
        Message  = $line
        Property = @{ Part = $Part.Name; State = $Part.State; Hidden = [bool] $Run['hidden'] }
    }
    Write-XmipAudit @audited
    Write-XmipDemoRecord -Run $Run
}
