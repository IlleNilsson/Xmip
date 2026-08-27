#requires -PSEdition Core
#requires -Version 7.6

<#
.SYNOPSIS
    What forty-two repositories need instead of `git status` and `git push`.

.DESCRIPTION
    Two commands, named and parameterised to read like the git underneath them.

        Get-XmipStatus                  git status, across the estate
        Publish-XmipChange -m '...'     git add, commit and push, in dependency
                                        order, having tested first

    Neither asks the caller to know anything git would not have asked. The
    dependency order is read out of the manifests, because it is already written
    there and making a person supply it is how the estate grows gray hairs.

    Style: docs/governance/powershell-style.md
#>

function Get-XmipStatus {
    <#
        .SYNOPSIS
            `git status`, across the estate.

        .DESCRIPTION
            Every module that has something uncommitted, what it is, and whether
            it looks like source or like build output.

            Objects out, not text. `Get-XmipStatus | Where-Object Suspicious`
            answers "is anything about to commit a target directory again"
            without parsing anything.

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
    [OutputType([PSCustomObject])]
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

        # posh-git separates staged from unstaged, and calls untracked files
        # Working.Added. Both matter here: `add -A` will take all of them.
        # The array subexpression wraps the whole pipeline, not just the
        # addition. Sort-Object emits a scalar for one item and nothing for
        # none, and under StrictMode neither has a Count.
        $files = @(
            @($git.Index.Added) + @($git.Index.Modified) + @($git.Index.Deleted) +
            @($git.Working.Added) + @($git.Working.Modified) + @($git.Working.Deleted) |
                Where-Object { $_ } |
                Sort-Object -Unique
        )

        $behind = $git.BehindBy -gt 0

        if ($files.Count -eq 0 -and -not $behind -and $git.AheadBy -eq 0) {
            continue
        }

        $suspicious = @($files | Where-Object { Test-XmipBuildOutput -Path $_ })

        if ($Short) {
            [PSCustomObject]@{
                Module     = $module
                Branch     = $git.Branch
                Changed    = $files.Count
                AheadBy    = $git.AheadBy
                BehindBy   = $git.BehindBy
                Suspicious = $suspicious.Count -gt 0
            }

            continue
        }

        foreach ($file in $files) {
            [PSCustomObject]@{
                Module     = $module
                Branch     = $git.Branch
                State      = Get-XmipFileState -Status $git -Path $file
                Path       = $file
                Suspicious = [bool] (Test-XmipBuildOutput -Path $file)
            }
        }
    }
}

function Publish-XmipChange {
    <#
        .SYNOPSIS
            `git add`, `commit` and `push` across every changed module, in
            dependency order, having tested first.

        .DESCRIPTION
            **Order is read, not asked for.** Dependencies track `branch =
            "main"` under ADR-0005, so a module has to be on origin before
            anything that depends on it is tested — otherwise the test resolves
            the previous version and passes or fails for the wrong reason. Every
            manifest already declares its dependencies, so the order comes from
            there.

            **Nothing lands unless everything passes.** A half-landed estate is
            worse than an unlanded one, for the same reason.

            **Build output is refused rather than committed.** On 2026-08-27 a
            hand-run loop pushed 105 files of `target/` to xmip-core: it checked
            whether a module was dirty and never what was dirty.

            Redirect to capture, per the style document:

                Publish-XmipChange -m 'what changed' *>&1 |
                    Tee-Object -FilePath D:\Repos\land.log

        .PARAMETER Message
            The commit message. Positional and aliased `-m`, like git. Short and
            precise — the reasoning belongs in the decision record.

        .PARAMETER All
            Include modules with no tests of their own. Without it, a module
            that cannot be verified here is reported and left alone.

        .PARAMETER NoVerify
            Land without testing, like `git commit --no-verify`. For a change no
            compiler can check.

        .PARAMETER RepositoryRoot
            The Xmip working tree.

        .EXAMPLE
            Publish-XmipChange -m 'Operate is the fourth purpose' -WhatIf

        .EXAMPLE
            Publish-XmipChange 'Identities are configured per purpose'

        .EXAMPLE
            Publish-XmipChange -m 'Fix a typo in the README' -NoVerify
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('m')]
        [ValidateNotNullOrEmpty()]
        [string] $Message,

        [Parameter()]
        [switch] $All,

        [Parameter()]
        [switch] $NoVerify,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $RepositoryRoot = (Get-XmipRepositoryRoot)
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Not $all. PowerShell variable names are case-insensitive, so that name
    # overwrites the -All switch parameter and the next call hands an array to
    # a [switch].
    $estate = @(Get-XmipStatus -RepositoryRoot $RepositoryRoot -Short)

    # The platform repository is landed by the pin step rather than as a
    # module, because its commit has to be last: it records where the modules
    # ended up.
    $status = @($estate | Where-Object { $_.Module -ne '.' -and $_.Changed -gt 0 })

    # Ahead means committed and not pushed — from an interrupted run, usually.
    # Landing continues; this only says so, because it is the difference
    # between "nothing happened" and "the last run stopped halfway".
    $unpushed = @($estate | Where-Object { $_.Changed -eq 0 -and $_.AheadBy -gt 0 })

    foreach ($module in $unpushed) {
        Write-Warning "$($module.Module) is $($module.AheadBy) commit(s) ahead of origin and has nothing uncommitted."
    }

    $stale = @($estate | Where-Object { $_.BehindBy -gt 0 })

    foreach ($module in $stale) {
        Write-Warning "$($module.Module) is $($module.BehindBy) commit(s) behind origin. Pull before landing."
    }

    $platform = @($estate | Where-Object { $_.Module -eq '.' -and $_.Changed -gt 0 })

    if ($status.Count -eq 0 -and $platform.Count -eq 0) {
        Write-Host 'Nothing to land.' -ForegroundColor DarkGray
        return
    }

    if ($status.Count -eq 0) {
        Write-Host 'Only the platform repository has changes.' -ForegroundColor Cyan
        Publish-XmipPin -RepositoryRoot $RepositoryRoot -Count 0 -Message $Message

        return [PSCustomObject]@{ Landed = @(); Verified = $false }
    }

    $suspect = @($status | Where-Object Suspicious)

    if ($suspect.Count -gt 0) {
        Write-Host 'Refusing. These have changes that look like build output:' -ForegroundColor Red
        $suspect | ForEach-Object { Write-Host "  $($_.Module)" }
        Write-Host ''
        Write-Host 'Get-XmipStatus | Where-Object Suspicious    shows which files.'
        Write-Host 'Add them to .gitignore, then run again.'

        return
    }

    $ordered = @(
        Sort-XmipModuleDependency -RepositoryRoot $RepositoryRoot -Module $status.Module
    )

    Write-Host "Landing $($ordered.Count) module(s), dependencies first:" -ForegroundColor Cyan
    $ordered | ForEach-Object { Write-Host "  $_" }

    $failed = @(
        if ($NoVerify) { @() }
        else { Test-XmipModule -RepositoryRoot $RepositoryRoot -Module $ordered -All:$All }
    )

    if ($failed.Count -gt 0) {
        Write-Host ''
        Write-Host 'Refusing. These did not pass:' -ForegroundColor Red
        $failed | ForEach-Object { Write-Host "  $_" }
        Write-Host ''
        Write-Host 'Nothing landed. The estate is exactly as it was.'

        return
    }

    $landed = @(
        Submit-XmipModule -RepositoryRoot $RepositoryRoot -Module $ordered -Message $Message
    )

    Publish-XmipPin -RepositoryRoot $RepositoryRoot -Count $landed.Count

    [PSCustomObject]@{
        Landed   = $landed
        Verified = -not $NoVerify
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

function Get-XmipFileState {
    <#
        .SYNOPSIS
            Two characters, index then working tree, as git prints them.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Status,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $index =
        if ($Status.Index.Added -contains $Path) { 'A' }
        elseif ($Status.Index.Modified -contains $Path) { 'M' }
        elseif ($Status.Index.Deleted -contains $Path) { 'D' }
        else { ' ' }

    # posh-git puts untracked files in Working.Added, which git prints as ??.
    $working =
        if ($Status.Working.Added -contains $Path) { '?' }
        elseif ($Status.Working.Modified -contains $Path) { 'M' }
        elseif ($Status.Working.Deleted -contains $Path) { 'D' }
        else { ' ' }

    "$index$working"
}

function Test-XmipBuildOutput {
    <#
        .SYNOPSIS
            Whether a changed path is something a compiler produced.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $Path -match '^(target/|bin/|obj/|\.vs/|Cargo\.lock$|packages\.lock\.json$)'
}

function Get-XmipDeclaredModule {
    <#
        .SYNOPSIS
            Every submodule path in .gitmodules, in file order.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    $modulesFile = Join-Path -Path $RepositoryRoot -ChildPath '.gitmodules'

    if (-not (Test-Path -LiteralPath $modulesFile)) {
        throw "No .gitmodules under $RepositoryRoot. Is that the Xmip working tree?"
    }

    $matchParams = @{
        Path    = $modulesFile
        Pattern = '^\s*path\s*=\s*(?<path>.+)$'
    }

    Select-String @matchParams |
        ForEach-Object { $_.Matches[0].Groups['path'].Value.Trim() }
}

function Sort-XmipModuleDependency {
    <#
        .SYNOPSIS
            Orders modules so that nothing is landed before what it depends on.

        .DESCRIPTION
            Reads each manifest's package name and its Xmip dependencies, then
            walks depth first. A module whose dependencies are all outside the
            set being landed comes first; everything else follows what it needs.

            A cycle is reported rather than silently broken. Cargo would refuse
            it anyway, and a quiet arbitrary order here would turn a manifest
            error into a mysterious build failure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Module
    )

    $package = @{}
    $needs = @{}

    foreach ($module in $Module) {
        $manifest = Join-Path -Path $RepositoryRoot -ChildPath "$module/Cargo.toml"

        if (-not (Test-Path -LiteralPath $manifest)) {
            # No manifest, no declared dependencies. Lands whenever.
            $needs[$module] = @()
            continue
        }

        $text = Get-Content -LiteralPath $manifest -Raw

        if ($text -match '(?m)^name\s*=\s*"(?<name>[^"]+)"') {
            $package[$Matches['name']] = $module
        }

        $needs[$module] = @(
            [regex]::Matches($text, '(?m)^\s*(?<alias>xmip[a-z0-9-]*)\s*=\s*\{(?<body>[^}]*)\}') |
                ForEach-Object {
                    $body = $_.Groups['body'].Value

                    if ($body -match 'package\s*=\s*"(?<package>[^"]+)"') {
                        $Matches['package']
                    }
                    else {
                        $_.Groups['alias'].Value
                    }
                }
        )
    }

    $ordered = [System.Collections.Generic.List[string]]::new()
    $state = @{}

    function Add-XmipModuleInOrder {
        param([string] $Current, [string[]] $Trail)

        if ($state[$Current] -eq 'done') { return }

        if ($state[$Current] -eq 'walking') {
            $cycle = ($Trail + $Current) -join ' -> '
            throw "The manifests declare a dependency cycle: $cycle"
        }

        $state[$Current] = 'walking'

        foreach ($dependency in $needs[$Current]) {
            $inSet = $package[$dependency]

            if ($inSet -and $inSet -ne $Current) {
                Add-XmipModuleInOrder -Current $inSet -Trail ($Trail + $Current)
            }
        }

        $state[$Current] = 'done'
        $ordered.Add($Current)
    }

    foreach ($module in $Module) {
        Add-XmipModuleInOrder -Current $module -Trail @()
    }

    $ordered
}

function Test-XmipModule {
    <#
        .SYNOPSIS
            Runs each module's own tests. Returns the ones that failed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Module,

        [Parameter()]
        [switch] $All
    )

    foreach ($module in $Module) {
        $path = Join-Path -Path $RepositoryRoot -ChildPath $module
        $manifest = Join-Path -Path $path -ChildPath 'Cargo.toml'

        if (-not (Test-Path -LiteralPath $manifest)) {
            $note = if ($All) { 'landing anyway' } else { 'nothing here can test it' }
            Write-Host "== $module (no Cargo.toml, $note)" -ForegroundColor DarkGray

            if (-not $All) { $module }

            continue
        }

        Write-Host "== $module" -ForegroundColor Cyan

        Push-Location -LiteralPath $path

        try {
            # Dependencies track main, so the lock is re-resolved or the test
            # runs against whatever was current when anyone last built.
            & cargo update 2>&1 | Out-Null

            # Captured, not emitted. This function returns the modules that
            # failed; a native command left to write into the pipeline makes
            # every line of its output a return value, and the caller reads
            # cargo's passing tests as the list of failures.
            $output = & cargo test 2>&1
            $passed = $LASTEXITCODE -eq 0
        }
        finally {
            Pop-Location
        }

        # Information stream, so it reaches the console and any redirect.
        $output | ForEach-Object { Write-Host $_ }

        if (-not $passed) {
            $module
        }
    }
}

function Submit-XmipModule {
    <#
        .SYNOPSIS
            Commits and pushes each module, in the order given.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Module,

        [Parameter(Mandatory)]
        [string] $Message
    )

    foreach ($module in $Module) {
        $path = Join-Path -Path $RepositoryRoot -ChildPath $module

        if (-not $PSCmdlet.ShouldProcess($module, 'commit and push')) {
            continue
        }

        # A submodule at a bare commit has no branch to push to.
        $branch = (& git -C $path branch --show-current) -join ''

        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-Host "   detached HEAD, checking out main" -ForegroundColor Yellow
            & git -C $path checkout main
        }

        & git -C $path add -A
        & git -C $path commit -m $Message --quiet
        & git -C $path push origin main --quiet

        if ($LASTEXITCODE -ne 0) {
            throw "Pushing $module failed. Anything before it is already on origin; fix this and run again."
        }

        Write-Host "   landed" -ForegroundColor Green
        $module
    }
}

function Publish-XmipPin {
    <#
        .SYNOPSIS
            Moves the superproject's gitlinks to where the modules now are.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [int] $Count,

        [Parameter()]
        [string] $Message
    )

    if (-not $PSCmdlet.ShouldProcess('the estate', 'pin and push')) {
        return
    }

    & git -C $RepositoryRoot add -A

    $staged = & git -C $RepositoryRoot status --porcelain

    if ([string]::IsNullOrWhiteSpace(($staged -join ''))) {
        Write-Host 'Estate already pinned.' -ForegroundColor DarkGray
        return
    }

    $noun = if ($Count -eq 1) { 'module' } else { 'modules' }

    $subject =
        if ($Count -eq 0 -and $Message) { $Message }
        else { "Pin $Count $noun" }

    & git -C $RepositoryRoot commit -m $subject --quiet
    & git -C $RepositoryRoot push origin main --quiet

    if ($LASTEXITCODE -ne 0) {
        throw 'Pushing the estate failed. The modules are landed; only the pin is missing.'
    }

    if ($Count -eq 0) {
        Write-Host 'Platform repository landed.' -ForegroundColor Green
    }
    else {
        Write-Host "Pinned $Count $noun." -ForegroundColor Green
    }
}
