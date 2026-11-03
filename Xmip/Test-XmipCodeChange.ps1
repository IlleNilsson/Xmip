#requires -PSEdition Core
#requires -Version 7.7.0

function Test-XmipCodeChange {
    <#
        .SYNOPSIS
            Whether a module's change can change what a consumer of it does:
            false only where every changed line is a comment, or every
            changed file Markdown or under doc/.

        .DESCRIPTION
            A comment-only change in a low module made the landing check all
            255 modules above it, an hour for nothing (the owner, 2026-11-02:
            *Go ahead, speed it up*). The module itself is still verified,
            doctests included; only its consumers are spared. Anything this
            cannot read as a comment — a line beside code, a block comment,
            a binary file, a new file outside doc/, a commit not yet pushed —
            is a code change.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Module
    )

    [string] $path = Join-Path -Path $RepositoryRoot -ChildPath $Module
    [scriptblock] $prose = { param([string] $file) $file -like '*.md' -or $file -like 'doc/*' }

    try {
        # Committed and not pushed: what it changed is not in the diff below.
        [string] $ahead = Invoke-XmipGit -At $path -Arguments @('rev-list', '--count', '@{u}..HEAD')

        if ($ahead.Trim() -ne '0') {
            return $true
        }

        [string[]] $untracked = @(
            Invoke-XmipGit -At $path -Arguments @('ls-files', '--others', '--exclude-standard')
        )

        if (@($untracked | Where-Object { -not (& $prose $_) }).Count -gt 0) {
            return $true
        }

        [string[]] $rows = @(
            Invoke-XmipGit -At $path -Arguments @('diff', 'HEAD', '--numstat', '--no-renames')
        )

        foreach ($row in $rows) {
            [string[]] $cells = $row -split "`t", 3
            [string] $file = $cells[2]

            if (& $prose $file) {
                continue
            }

            [string] $comment = switch -Wildcard ($file) {
                '*.rs' { '//' }
                '*.cs' { '//' }
                '*.ps1' { '#' }
                '*.psm1' { '#' }
                '*.toml' { '#' }
                '*.yml' { '#' }
                default { '' }
            }

            if ($cells[0] -eq '-' -or -not $comment) {
                return $true
            }

            [string[]] $changed = @(
                Invoke-XmipGit -At $path -Arguments @(
                    'diff', 'HEAD', '-U0', '--no-renames', '--', $file) |
                    Where-Object { $_ -match '^[+-]' -and $_ -notmatch '^(\+\+\+|---) ' } |
                    ForEach-Object { $_.Substring(1).Trim() } |
                    Where-Object { $_ -ne '' -and -not $_.StartsWith($comment) }
            )

            if ($changed.Count -gt 0) {
                return $true
            }
        }
    }
    catch {
        # git could not say: a new module, no upstream. Check every consumer.
        return $true
    }

    $false
}
