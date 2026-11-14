#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Assert-XmipOperationWebFree {
    <#
        .SYNOPSIS
            Refuses to start a web host on an address something already
            answers at, and says who holds it.

        .DESCRIPTION
            A second host on a held address dies at once and says nothing, and
            the first keeps answering with whatever it was started over (the
            owner's console, 2026-09-19).

        .PARAMETER Url
            The address the host is to bind.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Url
    )

    if (-not (Test-XmipOperationWebAnswering -Url $Url)) {
        return
    }

    [string] $held = (Get-XmipOperationWeb | ForEach-Object -MemberName Id) -join ', '
    [string] $who = 'another process holds it'

    if ($held) {
        $who = "xmip-gui-web pid $held runs"
    }

    throw "REFUSED. $Url already answers: $who. Stop-XmipOperationWeb ends ours."
}
