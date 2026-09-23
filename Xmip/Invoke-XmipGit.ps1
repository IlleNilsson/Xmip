#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The one way the module runs git.

.DESCRIPTION
    Until 2026-09-23 the module ran git five ways: Invoke-Git, Test-GitCommand
    and Get-GitLine in Invoke-Distribute.ps1, Invoke-Native in
    Invoke-GitHubApi.ps1, and `& git` written out forty times. The written-out
    calls checked $LASTEXITCODE where someone remembered to: Publish-XmipPin
    checked it only after a push, so a commit that failed, followed by a push
    with nothing to push, reported the estate pinned (open-problems.md,
    problem 25, row l).

    Style: doc/governance/powershell-style.md
#>

<#
    .SYNOPSIS
    Runs git and returns what it wrote to standard output, or throws.

    .DESCRIPTION
    A failure throws with the command, where it ran and everything git said,
    so no caller can go on as if it had worked. Standard error is not returned:
    git writes warnings there (line endings, detached heads) that are not an
    answer, and mixing them into one was how a warning once read as a path.

    -Test asks rather than acts: it returns whether git succeeded and throws
    nothing, for the questions git answers with its exit code alone —
    `diff --quiet`, `rev-parse --verify`.

    .PARAMETER At
    The working tree to run in, as `git -C`. Omitted for a command that makes
    one, such as clone.

    .PARAMETER Arguments
    What follows `git`.

    .PARAMETER Test
    Return success as a boolean instead of output, and never throw.
#>
function Invoke-XmipGit {
    [CmdletBinding()]
    [OutputType([string], [bool])]
    param(
        [Parameter()]
        [string] $At = '',

        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,

        [Parameter()]
        [switch] $Test
    )

    [string[]] $where = if ('' -ne $At) { @('-C', $At) } else { @() }
    [object[]] $said = @(& git @where @Arguments 2>&1)
    [bool] $succeeded = 0 -eq $LASTEXITCODE

    if ($Test) {
        return $succeeded
    }

    if (-not $succeeded) {
        [string] $place = if ('' -ne $At) { " in $At" } else { '' }
        [string] $detail = ($said | ForEach-Object { [string] $_ }) -join [Environment]::NewLine

        throw "git $($Arguments -join ' ')$place failed:$([Environment]::NewLine)$detail"
    }

    $said |
        Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } |
        ForEach-Object { [string] $_ }
}
