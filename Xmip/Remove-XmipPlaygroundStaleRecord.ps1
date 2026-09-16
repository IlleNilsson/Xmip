#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Remove-XmipPlaygroundStaleRecord {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $layout = Get-XmipPlaygroundLayout

    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Filter 'roll-*.toml' -File)) {
        [string] $number = $file.BaseName -replace '^roll-', ''

        if ($number -notmatch '^\d+$') { continue }

        $process = Get-Process -Id ([int] $number) -ErrorAction SilentlyContinue
        [bool] $alive = $null -ne $process -and
            (Test-XmipPlaygroundBinary -Process $process -Path $layout.Roll)

        if (-not $alive) { Remove-Item -LiteralPath $file.FullName -Force }
    }
}
