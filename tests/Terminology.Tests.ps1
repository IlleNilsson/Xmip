#Requires -Version 7.0

# Wording, not length. The estate's names are settled (docs/terminology.md);
# this test keeps a settled-but-overloaded word from drifting back into
# ambiguity. ADR-0035.
#
# The instrument is the ratchet from Rust.Style.Tests.ps1, pointed at prose
# instead of lines: a frozen count that may fall and must never rise. It does
# not judge whether a given bare use reads clearly — a lint cannot — so it does
# not force the historical uses to be rewritten. It forbids a NEW unqualified
# use, and every edit to an old record is a chance to qualify its uses and lower
# the ceiling.
#
# It counts a use, not a mention: the word wrapped in quotes, backticks or
# markdown emphasis is the word discussed as a word (as this file and the record
# do), not a concept left ambiguous, so it does not count.

BeforeAll {
    $script:DocsRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' 'docs')).Path

    # Built in pieces so each rule is legible and no line runs long.
    $mtn = '(?<!["`*])'                                       # not a mention, before
    $qual = '(?<!(Xmip|Host|System|Sending|Receiving|Business) )'
    $mtnAfter = '(?!["`*])'                                   # not a mention, after
    $axis = '(?! (Definition|Instance))'                      # the Definition/Instance axis

    $script:Watchwords = @(
        [pscustomobject]@{
            Word = 'Process'
            Pattern = [regex]($mtn + $qual + '\bProcess\b' + $mtnAfter + $axis)
            # Frozen 2026-09-06 at the count then present across docs. It may
            # fall, never rise. Qualify a new one (Xmip Process / Host Process /
            # System Process / Process Definition); do not raise this number.
            Ceiling = 99
        }
    )

    function Measure-Watchword {
        param([regex] $Pattern)

        [int] $sum = 0
        foreach ($file in Get-ChildItem -Path $script:DocsRoot -Recurse -Filter *.md) {
            $text = Get-Content -Raw -LiteralPath $file.FullName
            $sum += $Pattern.Matches($text).Count
        }
        $sum
    }
}

Describe 'Terminology: the glossary carries the disambiguation' {
    It 'keeps terminology.md defining the senses of Process' {
        $file = Join-Path $script:DocsRoot 'terminology.md'
        $terminology = Get-Content -Raw -LiteralPath $file

        $terminology | Should -Match 'Process terminology'
        $terminology | Should -Match 'bare word \*\*Process\*\* is ambiguous'
        foreach ($sense in @('System Process', 'Xmip Service', 'Xmip Process', 'Host Process')) {
            $terminology | Should -Match ([regex]::Escape($sense))
        }
    }
}

Describe 'Terminology: a settled but overloaded word stays qualified' {
    It 'does not let a bare watchword grow past its frozen ceiling' {
        foreach ($w in $script:Watchwords) {
            [int] $count = Measure-Watchword -Pattern $w.Pattern

            [string] $because =
                "bare unqualified '$($w.Word)' is frozen at $($w.Ceiling); a new " +
                'one must be qualified, not added to the ceiling'

            $count | Should -BeLessOrEqual $w.Ceiling -Because $because
        }
    }

    It 'has the ceiling no higher than the debt, so it only ever falls' {
        foreach ($w in $script:Watchwords) {
            [int] $count = Measure-Watchword -Pattern $w.Pattern

            [string] $because =
                "bare '$($w.Word)' is now $count; lower the ceiling to match so " +
                'the next unqualified use is caught'

            $w.Ceiling | Should -BeLessOrEqual $count -Because $because
        }
    }
}
