#requires -Version 7.7.0

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    What Start-XmipTest's -Suite and -Test complete to.

.DESCRIPTION
    A completer runs in the caller's scope, so each asks the module for its
    words through these. Apart from Get-XmipTestSuite.ps1 since 2026-11-10,
    when that file reached the 400 lines the estate allows a file.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipTestChoice {
    <#
        .SYNOPSIS
            The tests Start-XmipTest's -Test completes to, for the suite named
            so far. Private; the completer asks the module for it.

        .PARAMETER Suite
            The suite typed so far; empty is the Essentials.

        .PARAMETER Word
            What has been typed of the test.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Suite = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Word = ''
    )

    # Qualified or bare, both name the estate's suite, and Core.Estate is the
    # spelling (ADR-0059, amendment 2026-09-20); omitted, -Suite is the
    # Essentials.
    [string[]] $names = if ($Suite -ieq 'Estate' -or $Suite -ieq 'Core.Estate') {
        [string] $root = Get-XmipRepositoryRoot
        Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'test') -Filter '*.Test.ps1' |
            ForEach-Object { $_.Name -replace '\.Test\.ps1$', '' }
    }
    elseif ($Suite -ieq 'Demo' -or $Suite -ieq $script:XmipDemoSuite) {
        @()
    }
    else {
        @($script:XmipEssentialsTest.Keys)
    }

    $names | Where-Object { $_ -like "$Word*" }
}


function Get-XmipTestSuiteChoice {
    <#
        .SYNOPSIS
            The suites Start-XmipTest's -Suite completes to. Private; a
            completer runs in the caller's scope, so it asks the module.

        .PARAMETER Word
            What has been typed of the suite.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Word = ''
    )

    Get-XmipTestSuite | ForEach-Object { $_.Name } | Where-Object { $_ -like "$Word*" }
}
