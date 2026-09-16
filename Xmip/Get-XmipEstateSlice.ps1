#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipEstateSlice {
    [CmdletBinding()]
    [OutputType('Xmip.EstateSlice')]
    param(
        [Parameter()]
        [string] $Slice,

        [Parameter()]
        [string] $SliceRoot = (Join-Path (Get-XmipRepositoryRoot) '.local-work/estate')
    )

    if (-not (Test-Path -LiteralPath $SliceRoot -PathType Container)) { return }

    Import-Module PSToml -ErrorAction Stop
    [string] $filter = if ([string]::IsNullOrWhiteSpace($Slice)) { '*.toml' } else { "$Slice.toml" }

    foreach ($file in @(Get-ChildItem -LiteralPath $SliceRoot -Filter $filter -File)) {
        $value = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8 | ConvertFrom-Toml

        [PSCustomObject]@{
            PSTypeName = 'Xmip.EstateSlice'
            Slice = [string](Get-TomlValue -Node $value -Name 'slice' -Default '')
            Path = [string](Get-TomlValue -Node $value -Name 'path' -Default '')
            Include = @(Get-TomlValue -Node $value -Name 'include' -Default @())
            Repository = @(Get-TomlValue -Node $value -Name 'repository' -Default @())
            Definition = $file.FullName
        }
    }
}
