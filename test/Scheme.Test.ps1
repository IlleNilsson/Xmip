#requires -PSEdition Core
#requires -Version 7.7.0

<#
    Every cloud technology's scheme is its name. A transport that is one
    vendor's service carries the vendor's token first (ADR-0011, amendment
    2026-11-17), and the scheme a Location's address is entered with, which
    chooses the technology (ADR-0064, amendment 2026-10-28), is that name
    too, the vendor included (ADR-0011, amendment 2026-11-19): until that
    day three were not, Kinesis, Cloud Storage and Pub/Sub each answering a
    word of its own.

    Every transport mounted at module/core/capability/transport/<vendor>-*
    is read for the schemes its Configured::SCHEMES declares, and its folder
    name, which is its technology's name, must be one of them.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # The vendors whose services the estate carries as transports, each a
    # token of the standard slot (ADR-0011, amendment 2026-11-17).
    [string[]] $script:Vendor = @('aws', 'azure', 'google')
    [string] $first = "^($($script:Vendor -join '|'))-"
    [string] $transport = Join-Path $script:Root 'module/core/capability/transport'
    $script:Cloud = @(
        Get-ChildItem -LiteralPath $transport -Directory | Where-Object Name -Match $first
    )
}

Describe 'A cloud technology''s scheme' {
    It 'is its name, for every vendor''s transport' {
        [string] $declared = 'const\s+SCHEMES\s*:[^=]*=\s*&\[(?<schemes>[^\]]*)\]'
        [string[]] $wrong = @(
            foreach ($folder in $script:Cloud) {
                [string] $src = Join-Path $folder 'src'
                [string] $source = (Get-ChildItem -LiteralPath $src -Filter '*.rs' -Recurse |
                    Get-Content -Raw) -join "`n"
                [string[]] $schemes = @(
                    [regex]::Matches($source, $declared) | ForEach-Object {
                        [regex]::Matches($_.Groups['schemes'].Value, '"([^"]*)"') |
                            ForEach-Object { $_.Groups[1].Value }
                    }
                )
                if ($folder.Name -notin $schemes) {
                    "$($folder.Name) declares SCHEMES [$($schemes -join ', ')]"
                }
            }
        )

        $wrong | Should -BeNullOrEmpty -Because (
            "a cloud technology's scheme is its name, the vendor included " +
            "(ADR-0011, amendment 2026-11-19):`n" + ($wrong -join "`n"))
    }

    It 'reads every vendor''s transports, so the check is not passing on nothing' {
        @($script:Cloud | ForEach-Object { ($_.Name -split '-')[0] } | Sort-Object -Unique) |
            Should -Be $script:Vendor
    }
}
