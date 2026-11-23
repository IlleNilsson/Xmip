#requires -Version 7.7.0

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Ending a run that is one detached pwsh, for Stop-XmipTest.

.DESCRIPTION
    Apart from Stop-XmipTest.ps1 since 2026-11-23, when -ComputerName took the
    room that file had left.

    Style: doc/governance/powershell-style.md
#>


function Stop-XmipDetachedRun {
    <#
        .SYNOPSIS
            Ends a run that is one detached pwsh — an estate run, a run of
            the internal tests, or a roll still building: that pwsh and
            everything it started, then its record.

        .DESCRIPTION
            A test may start a process of its own — cargo, a node, a host —
            and a build is cargo and its compilers, so ending only the pwsh
            would orphan them: the whole tree is ended, as Stop-XmipTest ends
            a roll's tree. The log is kept, for what the run said before it
            was stopped.

        .PARAMETER Run
            The run, from Get-XmipEstateRun or Get-XmipSystemTestBuild.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Run
    )

    try {
        [System.Diagnostics.Process]::GetProcessById($Run.Id).Kill($true)
    }
    catch {
        [string] $why = $_.Exception.Message
        Write-Error "REFUSED: $($Run.Suite) run $($Run.Id) could not be stopped: $why"
        return
    }

    Wait-Process -Id $Run.Id -Timeout 5 -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Run.Record -Force -ErrorAction SilentlyContinue
    Write-Verbose "stopped the $($Run.Suite) run $($Run.Id)"
}
