#requires -PSEdition Core
#requires -Version 7.6.7

<#
    The estate holds no hand-written JavaScript. TypeScript lives in the VS
    Code extension's shell and nowhere else (the owner, 2026-09-10: *keep
    TypeScript and JavaScript only to the VS Code extension*), and there it
    is TypeScript too (the owner, 2026-10-22: *But not JavaScript.*; ADR-0014,
    amendment 2026-10-22): what runs as JavaScript is the compiler's output,
    build output that is never tracked. The extension's ESLint configuration
    was the last .mjs and became eslint.config.ts the same day.

    Every repository of the estate is asked what it tracks, the root and each
    submodule, so a .js, .mjs or .cjs file committed anywhere fails here.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
}

Describe 'JavaScript' {
    It 'is tracked nowhere in the estate' {
        [string[]] $tracked = @(
            git -C $script:Root ls-files --recurse-submodules -- '*.js' '*.mjs' '*.cjs'
        )

        $LASTEXITCODE | Should -Be 0 -Because 'git lists what every repository tracks'
        $tracked | Should -BeNullOrEmpty -Because (
            'the estate holds no hand-written JavaScript; write it in TypeScript in the ' +
            "VS Code extension, or in the language its module is written in:`n" +
            ($tracked -join "`n"))
    }
}
