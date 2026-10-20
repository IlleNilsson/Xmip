#requires -PSEdition Core
#requires -Version 7.6.7

function Test-XmipSpelling {
    <#
        .SYNOPSIS
            Checks spelling with typos and returns every finding, one line
            each; nothing when the spelling holds.

        .DESCRIPTION
            The estate's one spelling check. test/Spelling.Test.ps1 runs it
            over the whole estate and Test-XmipModule over each module a
            landing tests, both with the root's _typos.toml: the allowed
            words, the excluded files and the owner's quotes, which keep his
            spelling, are declared there once. A module is its own repository
            and carries no configuration, so the root's is named explicitly.

            typos is a prerequisite (prerequisite.toml, typos); a machine
            without it is refused by name rather than passing unchecked.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        # What to check, relative to the repository root; the whole estate
        # when omitted.
        [Parameter()]
        [string[]] $Path = @('.')
    )

    if (-not (Get-Command -Name 'typos' -ErrorAction SilentlyContinue)) {
        throw ('typos is not installed. It is the prerequisite typos in prerequisite.toml: ' +
            'Install-XmipPrerequisite, or winget install --id Crate-CI.Typos --exact.')
    }

    [string] $configuration = Join-Path -Path $RepositoryRoot -ChildPath '_typos.toml'

    Push-Location -LiteralPath $RepositoryRoot

    try {
        [string[]] $found = @(& typos --config $configuration --format brief -- @Path 2>&1 |
                ForEach-Object { "$_" })

        # 0 is clean and 2 is findings; anything else is typos failing, which
        # is not a clean answer either.
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 2) {
            throw "typos failed ($LASTEXITCODE): $($found -join [Environment]::NewLine)"
        }
    }
    finally {
        Pop-Location
    }

    return $found
}
