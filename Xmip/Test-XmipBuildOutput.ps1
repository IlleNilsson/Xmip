#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What a compiler produced, and the landing's refusal to commit it.

.DESCRIPTION
    Apart from Test-XmipModule.ps1 since 2026-11-19, when round 12's landing
    committed 483 files of .NET build output to xmip-core-cli,
    src/Xmip.Cli/bin and obj and src/Xmip.Cli.Test/bin and obj (38e46a4): the
    rule was anchored at a repository's root, an untracked folder was read as
    one path, and the platform repository was never asked (ADR-0060,
    amendment 2026-11-19).

    Style: doc/governance/powershell-style.md
#>


# Build output by its path: at a repository's root target/, bin/, .vs/,
# Cargo.lock and packages.lock.json; anywhere an obj folder, .NET's, which the
# source walk skips by name too (Get-XmipSourceFile); a bin folder holding
# Debug/ or Release/, in that case, since Rust's src/bin is source; and a
# compiled library, program, symbol file or package.
[string] $script:XmipBuildOutputPath = (
    '^(target|bin|\.vs)/|^(Cargo\.lock|packages\.lock\.json)$|(^|/)obj/' +
    '|(^|/)bin/(?-i:Debug|Release)/|\.(dll|exe|pdb|so|dylib|rlib|nupkg)$'
)

# What cargo writes in every build directory it makes, whatever its name.
[string] $script:XmipCacheTag = 'CACHEDIR.TAG'


function Test-XmipBuildOutput {
    <#
        .SYNOPSIS
            Whether a change in a repository adds or changes something a
            compiler produced. A deletion never does: it is how such a file
            leaves.

        .DESCRIPTION
            The estate's one rule for build output: $script:XmipBuildOutputPath
            by the path, and a target folder by what it holds, the CACHEDIR.TAG
            cargo writes in it. deploy/profile/target holds a deployment
            target's profiles, which are source, and a name match once lost
            them.

        .PARAMETER At
            The repository's working tree.

        .PARAMETER Path
            The changed path from the repository's root, as git names it; a
            folder ends in '/'.

        .PARAMETER State
            Its two-letter state, as Get-XmipRepositoryStatus reads it; one
            holding D is a deletion.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $At,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $State
    )

    if ($State.Contains('D')) {
        return $false
    }

    if ($Path -match $script:XmipBuildOutputPath) {
        return $true
    }

    # Every folder on the path, never its last part: a file named target is
    # no folder.
    [string[]] $part = $Path.Split('/')

    for ([int] $index = 0; $index -lt $part.Count - 1; $index++) {
        if ($part[$index] -ne 'target') {
            continue
        }

        [string] $folder = Join-Path -Path $At -ChildPath ($part[0..$index] -join '/')

        if (Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath $script:XmipCacheTag)) {
            return $true
        }
    }

    return $false
}


function Assert-XmipNoBuildOutput {
    <#
        .SYNOPSIS
            Refuses a landing that would commit build output in any
            repository, naming each and its first such files, before
            anything is verified or committed.

        .PARAMETER Status
            The estate as Get-XmipStatus -Short reads it.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Status
    )

    [int] $first = 5
    [object[]] $carrying = @($Status | Where-Object -Property Suspicious)

    if ($carrying.Count -eq 0) {
        return
    }

    [string[]] $said = @(
        'REFUSED. These would commit build output, and nothing was verified or landed:'

        foreach ($repository in $carrying) {
            [string[]] $file = @($repository.BuildOutput)
            [string] $name = $repository.Module

            if ($name -eq '.') {
                $name = 'the platform repository'
            }

            "  $name, $($file.Count) file(s):"
            $file | Select-Object -First $first | ForEach-Object { "    $_" }

            if ($file.Count -gt $first) {
                "    and $($file.Count - $first) more"
            }
        }

        'Delete them, or ignore them in that repository''s .gitignore, then run again.'
    )

    throw ($said -join "`n")
}
