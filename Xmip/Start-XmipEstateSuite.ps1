#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Start-XmipEstateSuite {
    <#
        .SYNOPSIS
            Runs selected Pester files in an isolated runspace and returns the result.
    #>
    [CmdletBinding()]
    [OutputType('Pester.Run')]
    param(
        [Parameter()]
        [string] $Path,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Test = @()
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path -Path (Get-XmipRepositoryRoot) -ChildPath 'test'
    }

    $configuration = Get-XmipPesterConfiguration -Path $Path

    if ($Test.Count -gt 0) {
        [string[]] $files = @(
            $Test | ForEach-Object { Join-Path -Path $Path -ChildPath "$_.Test.ps1" }
        )
        [string[]] $missing = @($files | Where-Object { -not (Test-Path -LiteralPath $_) })

        if ($missing.Count -gt 0) {
            throw "No such test: $($missing -join ', '). The tests are the *.Test.ps1 in $Path."
        }

        $configuration.Run.Path = $files
    }

    $job = Start-ThreadJob -ScriptBlock {
        param($Configuration)

        Set-StrictMode -Off
        Invoke-Pester -Configuration $Configuration
    } -ArgumentList $configuration

    $result = Receive-Job -Job $job -Wait -AutoRemoveJob
    [string] $tally = "$($result.PassedCount) passed, $($result.FailedCount) failed"

    if ($result.FailedCount -eq 0) {
        Write-Host "OK $tally" -ForegroundColor Green
    }
    else {
        Write-Host "FAILED $tally" -ForegroundColor Red
    }

    foreach ($failure in $result.Failed) {
        Write-Host "   FAILED $($failure.ExpandedPath)" -ForegroundColor Red
    }

    return $result
}
