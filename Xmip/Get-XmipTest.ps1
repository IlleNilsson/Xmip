#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipTest {
    <#
        .SYNOPSIS
            Reads one view of Xmip's test facilities and their results.

        .EXAMPLE
            Get-XmipTest -View Status

        .EXAMPLE
            Get-XmipTest -View Result -Worst
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus', 'Xmip.TestNode', 'Xmip.Web', 'Xmip.TestResult')]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Status', 'Node', 'Result', 'Monitor', 'History')]
        [string] $View = 'Status',

        [Parameter()]
        [string] $Path,

        [Parameter()]
        [string] $Name = '*',

        [Parameter()]
        [string[]] $Test,

        [Parameter()]
        [string[]] $Node,

        [Parameter()]
        [switch] $Worst,

        [Parameter()]
        [ValidateSet('streams', 'messages', 'bytes')]
        [string] $Counted,

        [Parameter()]
        [datetime] $Since
    )

    $ErrorActionPreference = 'Stop'

    switch ($View) {
        'Node' { return Get-XmipTestNode -Name $Name }
        'Monitor' { return Get-XmipWeb }
        'Result' { return Get-XmipTestResultView -Bound $PSBoundParameters }
        'History' { return Get-XmipTestHistoryView -Bound $PSBoundParameters }
        default {
            if ([string]::IsNullOrWhiteSpace($Path)) { return Get-XmipTestStatus }
            return Get-XmipTestStatus -Path $Path
        }
    }
}
