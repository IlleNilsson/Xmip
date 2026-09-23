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

    Import-XmipPoshGit

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

        Push-Location -LiteralPath $path

        try {
            $git = Get-GitStatus
        }
        finally {
            Pop-Location
        }

        if (-not $git) {
            Write-Warning "$module is not a git repository."
            continue
        }

        # posh-git for what porcelain does not have — branch, ahead, behind —
        # and porcelain for the files.
        #
        # Not both from posh-git. Get-GitStatus disables file status for
        # repositories it judges large and still answers HasWorking: False, so
        # its Index and Working sets read as "clean" when they mean "not
        # counted". On 2026-08-27 that hid two modified modules and cost three
        # rounds of a red build.
        [string[]] $porcelain = @(Invoke-XmipGit -At $path -Arguments @('status', '--porcelain'))
        $changed = @($porcelain | Where-Object { $_ })
        $files = @($changed | ForEach-Object { $_.Substring(3).Trim('"') } | Sort-Object -Unique)

        $behind = $git.BehindBy -gt 0

        if ($files.Count -eq 0 -and -not $behind -and $git.AheadBy -eq 0) {
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

        foreach ($line in $changed) {
            $file = $line.Substring(3).Trim('"')

            [PSCustomObject]@{
                PSTypeName = 'Xmip.Status'
                Module     = $module
                Branch     = $git.Branch
                State      = $line.Substring(0, 2)
                Path       = $file
                Suspicious = [bool] (Test-XmipBuildOutput -Path $file)
            }
        }
    }
}


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

function Import-XmipPoshGit {
    <#
        .SYNOPSIS
            Loads posh-git, and says how to get it when it is absent.

        .DESCRIPTION
            Imported on demand rather than declared in RequiredModules, for the
            same reason PSToml is: this module has to load on a machine that
            does not have its prerequisites yet, because
            Install-XmipPrerequisite is how they arrive.
    #>
    [CmdletBinding()]
    param()

    if (Get-Module -Name posh-git) {
        return
    }

    if (-not (Get-Module -ListAvailable -Name posh-git)) {
        throw @'
posh-git is not installed.

    Install-XmipPrerequisite -Role operator

or, on its own:

    Install-Module posh-git -Scope CurrentUser
'@
    }

    Import-Module -Name posh-git -ErrorAction Stop
}
