#requires -PSEdition Core
#requires -Version 7.6.7

<#
    The estate is spelled right, in American English, in every language it
    holds (the owner, 2026-10-19: *Scary, please do spellchecking.*). typos
    reads the root's _typos.toml: the words a standard or a test defines, each
    with its reason, the files that are build output, lock files or
    generated, and the owner's quotes, which keep his spelling. A module's
    landing runs the same check over that module (Test-XmipModule).
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
}

Describe 'Spelling' {
    It 'finds no misspelling anywhere in the estate' {
        # A machine without typos fails here, naming the prerequisite.
        [string[]] $found = @(& (Get-Module -Name Xmip) {
                param([string] $Root)
                Test-XmipSpelling -RepositoryRoot $Root
            } $script:Root)

        $found | Should -BeNullOrEmpty -Because (
            'typos, configured by _typos.toml, found these: fix each, or allow ' +
            "a word a standard defines there with its reason`n" + ($found -join "`n"))
    }
}
