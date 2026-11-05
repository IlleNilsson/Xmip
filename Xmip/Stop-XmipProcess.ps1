#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    How the module stops a process it started: given time to end on its own
    where it was asked to, then ended, then waited for. The one place it is
    written.

    Style: doc/governance/powershell-style.md
#>


# How long an ended process is waited for before the caller goes on.
[int] $script:XmipProcessGone = 5


function Stop-XmipProcess {
    <#
        .SYNOPSIS
            Stops the processes -Id names, after up to -Grace seconds for
            them to end on their own, and waits for them to be gone. An
            error stopping one follows the caller's -ErrorAction.

        .PARAMETER Id
            The processes.

        .PARAMETER Grace
            Seconds to wait first, for processes already asked to stop, such
            as by a stop file. None by default.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [int[]] $Id,

        [int] $Grace = 0
    )

    if ($Grace -gt 0) {
        Wait-Process -Id $Id -Timeout $Grace -ErrorAction SilentlyContinue
    }

    [int[]] $running = @($Id | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })

    if ($running.Count -eq 0) {
        return
    }

    Stop-Process -Id $running -Force
    Wait-Process -Id $running -Timeout $script:XmipProcessGone -ErrorAction SilentlyContinue
}
