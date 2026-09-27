#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    What git status says, across every repository of the estate at once.

.DESCRIPTION
    Apart from Publish-XmipChange.ps1 since 2026-09-22, when that file had grown
    to 1,586 lines against the 400 the estate allows a file, and the owner asked
    for the estate to be consolidated. The landing is one command made of several
    subjects; each subject is a file.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipStatus {
    <#
        .SYNOPSIS
            `git status`, across the estate.

        .DESCRIPTION
            Every module that has something uncommitted, what it is, and whether
            it looks like source or like build output.

            Objects out, not text, so
            `Get-XmipStatus | Where-Object Suspicious` answers "is anything
            about to commit a target directory again" without parsing anything.

        .PARAMETER Short
            One line per module rather than one per file. Mirrors
            `git status --short`.

        .PARAMETER RepositoryRoot
            The Xmip working tree. Defaults to the one this module was imported
            from.

        .EXAMPLE
            Get-XmipStatus

        .EXAMPLE
            Get-XmipStatus -Short

        .EXAMPLE
            Get-XmipStatus | Where-Object Suspicious
    #>
    [CmdletBinding()]
    [OutputType('Xmip.Status', 'Xmip.StatusSummary')]
    param(
        [Parameter()]
        [switch] $Short,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $RepositoryRoot = (Get-XmipRepositoryRoot)
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # The platform repository first. It is a repository like the others, and it
    # holds the PowerShell module, the decision records and the assembly — the
    # things most likely to be uncommitted while every submodule is clean.
    $estate = @('.') + @(Get-XmipDeclaredModule -RepositoryRoot $RepositoryRoot)

    foreach ($module in $estate) {
        $path =
            if ($module -eq '.') { $RepositoryRoot }
            else { Join-Path -Path $RepositoryRoot -ChildPath $module }

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Warning "$module is declared and not present. Run Sync-XmipEstate."
            continue
        }

        if (-not (Test-Path -LiteralPath (Join-Path -Path $path -ChildPath '.git'))) {
            Write-Warning "$module is not a git repository."
            continue
        }

        $git = Get-XmipRepositoryStatus -At $path
        $files = @($git.Entry | ForEach-Object { $_.Path } | Sort-Object -Unique)

        if ($files.Count -eq 0 -and $git.BehindBy -eq 0 -and $git.AheadBy -eq 0) {
            continue
        }

        $suspicious = @($files | Where-Object { Test-XmipBuildOutput -Path $_ })

        if ($Short) {
            [PSCustomObject]@{
                PSTypeName = 'Xmip.StatusSummary'
                Module     = $module
                Branch     = $git.Branch
                Changed    = $files.Count
                AheadBy    = $git.AheadBy
                BehindBy   = $git.BehindBy
                Suspicious = $suspicious.Count -gt 0
            }

            continue
        }

        foreach ($entry in $git.Entry) {
            [PSCustomObject]@{
                PSTypeName = 'Xmip.Status'
                Module     = $module
                Branch     = $git.Branch
                State      = $entry.State
                Path       = $entry.Path
                Suspicious = [bool] (Test-XmipBuildOutput -Path $entry.Path)
            }
        }
    }
}


function Get-XmipRepositoryStatus {
    <#
        .SYNOPSIS
            Where one repository stands: its branch, its upstream, how far
            ahead and behind, and every changed file.

        .DESCRIPTION
            The estate's one reading of a repository's status, from one
            `git status --porcelain=v2 --branch`: Get-XmipStatus lists it for
            every repository, Sync-XmipRepository -Status prints it, and the
            pin asks it whether a committed pin is still to push.

            Branch is the branch, or the short commit when HEAD is detached,
            which Detached then says. HasUpstream is false for a branch that
            tracks nothing, and AheadBy and BehindBy are then 0. Entry is one
            object per changed path, State the two-letter code of
            `git status --short` ('??' for untracked) and Path the path, the
            new one for a rename. Changed counts tracked changes, Untracked
            the rest; Clean is true when there are none of either.

        .PARAMETER At
            The repository's working tree.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $At
    )

    [string[]] $said = @(
        Invoke-XmipGit -At $At -Arguments @('status', '--porcelain=v2', '--branch')
    )
    [hashtable] $branch = @{}
    [object[]] $entry = @(
        foreach ($line in $said) {
            if ($line -match '^# branch\.(\S+) (.*)$') {
                $branch[$Matches[1]] = $Matches[2]
                continue
            }

            ConvertFrom-XmipStatusLine -Line $line
        }
    )

    [string] $head = [string] $branch['head']
    [bool] $detached = $head -eq '(detached)'
    [int] $ahead = 0
    [int] $behind = 0

    if ([string] $branch['ab'] -match '^\+(\d+) -(\d+)$') {
        $ahead = [int] $Matches[1]
        $behind = [int] $Matches[2]
    }

    if ($detached) {
        $head = ([string] $branch['oid']).Substring(0, 7)
    }

    [int] $untracked = @($entry | Where-Object { $_.State -eq '??' }).Count

    return [pscustomobject] @{
        Branch      = $head
        Detached    = $detached
        HasUpstream = $branch.ContainsKey('upstream')
        AheadBy     = $ahead
        BehindBy    = $behind
        Entry       = $entry
        Changed     = $entry.Count - $untracked
        Untracked   = $untracked
        Clean       = $entry.Count -eq 0
    }
}


function ConvertFrom-XmipStatusLine {
    <#
        .SYNOPSIS
            One changed path from a line of `git status --porcelain=v2`, as
            State and Path; nothing for a line that names no path.

        .DESCRIPTION
            Version 2 puts a fixed number of fields before the path, by the
            line's kind: eight for an ordinary change, nine for a rename or a
            copy (whose original path follows a tab), ten for an unmerged path.
            Its '.' for an unchanged side is the ' ' of the short format.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Line
    )

    [hashtable] $fields = @{ '1' = 8; '2' = 9; 'u' = 10 }
    [string] $kind = if ($Line.Length -gt 1) { $Line.Substring(0, 1) } else { '' }
    [string] $state = ''
    [string] $path = ''

    if ($kind -eq '?' -or $kind -eq '!') {
        $state = "$kind$kind"
        $path = $Line.Substring(2)
    }
    elseif ($fields.ContainsKey($kind)) {
        [string[]] $part = $Line.Split(' ', $fields[$kind] + 1)
        $state = $part[1].Replace('.', ' ')
        $path = $part[-1].Split("`t")[0]
    }
    else {
        return
    }

    return [pscustomobject] @{
        State = $state
        Path  = $path.Trim('"')
    }
}
