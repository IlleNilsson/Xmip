#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Moving a submodule inside the estate, and repairing what the move leaves wrong.

.DESCRIPTION
    Lifted out of Invoke-Compose.ps1 on 2026-09-23, when moving every module under
    module/core/ taught it what Windows, editors and git itself do to a
    submodule that moves: held directories, half-finished git mv, nested git
    directories counted from the old depth. Invoke-Compose asks; this moves.

    Style: doc/governance/powershell-style.md
#>

<#
    .SYNOPSIS
    What `git mv` would have written about a submodule that moved.

    .DESCRIPTION
    A submodule is four facts in four places: where its working tree is
    (.gitmodules and the estate's config section), and where its git
    directory is (the .git file inside it, relatively, and that directory's
    own `core.worktree`, relatively back). A rename made by hand leaves all
    four saying the old path, and git then cannot open the submodule at all.
    Its own submodules count their levels the same way and are repaired with
    it.

    .PARAMETER Root
    The estate root.

    .PARAMETER From
    Where the submodule was.

    .PARAMETER To
    Where it is now.
#>
function Repair-XmipSubmoduleLink {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $From,

        [Parameter(Mandatory = $true)]
        [string] $To
    )

    [string] $modules = Join-Path $Root '.gitmodules'
    [string] $text = Get-Content -LiteralPath $modules -Raw

    $text = $text.Replace("[submodule `"$From`"]", "[submodule `"$To`"]")
    $text = $text.Replace("path = $From`n", "path = $To`n")
    Set-Content -LiteralPath $modules -Value $text -NoNewline

    # The estate's config may not name the submodule at all; then there is
    # nothing to rename, and that is not a failure.
    [string[]] $rename = @('config', '--rename-section', "submodule.$From", "submodule.$To")
    Invoke-XmipGit -At $Root -Arguments $rename -Test | Out-Null

    Repair-XmipGitPointer -Root $Root -Path $To

    # A submodule's own submodules keep their git directories in the estate's
    # .git too, counted from where they sit, so the move made every one of
    # them a level wrong as well. Found when logic's http-api and matter
    # could not be opened after the move under module/core/ (2026-09-23).
    foreach ($nested in Get-XmipNestedGit -Directory (Join-Path $Root $To)) {
        [string] $relative = [IO.Path]::GetRelativePath($Root, $nested)

        if (Test-Path -LiteralPath (Join-Path $nested '.git') -PathType Leaf) {
            Repair-XmipGitPointer -Root $Root -Path $relative.Replace('\', '/')
        }
    }
}


<#
    .SYNOPSIS
    Every working tree beneath a directory that has a .git of its own.

    .DESCRIPTION
    Build output is not walked: a crate's target/ holds tens of thousands of
    files and never a repository, and walking it took minutes a move.

    .PARAMETER Directory
    Where to look beneath; the directory itself is not reported.
#>
function Get-XmipNestedGit {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    foreach ($child in Get-ChildItem -LiteralPath $Directory -Directory -Force) {
        if ($child.Name -in @('target', 'bin', 'obj', 'node_modules', '.git')) {
            continue
        }

        if (Test-Path -LiteralPath (Join-Path $child.FullName '.git')) {
            $child.FullName
        }

        Get-XmipNestedGit -Directory $child.FullName
    }
}


<#
    .SYNOPSIS
    Point one .git file, and the git directory it names, at where it now is.

    .DESCRIPTION
    The .git file points at the estate's .git/modules/… with one ../ per level
    it sits under, and the git directory's `core.worktree` points back the same
    way. A file that points anywhere else is left alone.

    .PARAMETER Root
    The estate root.

    .PARAMETER Path
    The working tree, relative to the root, with forward slashes.
#>
function Repair-XmipGitPointer {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [string] $pointer = Join-Path $Root (Join-Path $Path '.git')
    [string] $said = (Get-Content -LiteralPath $pointer -Raw).Trim()
    [string] $inner = ($said -replace '^gitdir:\s*', '') -replace '^(\.\./)+', ''

    if (-not $inner.StartsWith('.git/')) {
        return
    }

    [string] $up = '../' * ($Path.Split('/').Count)
    Set-Content -LiteralPath $pointer -Value "gitdir: $up$inner"

    [string] $configuration = Join-Path (Join-Path $Root $inner) 'config'

    if (Test-Path -LiteralPath $configuration -PathType Leaf) {
        [string] $held = Get-Content -LiteralPath $configuration -Raw
        [string] $back = '../' * ($inner.Split('/').Count)

        $held = $held -replace 'worktree = [^
]*', "worktree = $back$Path"
        Set-Content -LiteralPath $configuration -Value $held -NoNewline
    }
}


<#
    .SYNOPSIS
    Move one submodule, whatever Windows thinks of the rename.

    .DESCRIPTION
    `git mv` is the whole move — the working tree, .gitmodules, the config
    section and the .git file's relative gitdir — and it is what this asks
    for first.

    It is refused with "Permission denied" where an editor holds a handle
    inside the directory: rust-analyzer in a crate's target/, a language
    server in a project's obj/. The same rename through a path beside it, on
    the same volume, is allowed, and git then records what moved. Found
    moving twenty-five modules under module/core/ on 2026-09-23, where four
    of them were refused and the rest were not.

    .PARAMETER Root
    The estate root.

    .PARAMETER From
    Where the submodule is, relative to the root.

    .PARAMETER To
    Where it belongs.
#>
function Move-XmipSubmodule {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $From,

        [Parameter(Mandatory = $true)]
        [string] $To
    )

    if (-not $PSCmdlet.ShouldProcess("$From -> $To", 'Move submodule')) {
        return
    }

    # git mv will not make the level module/core/ the day the provider enters
    # the path.
    [string] $parent = Split-Path -Parent (Join-Path $Root $To)

    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    # git's own fsmonitor daemon holds every working tree it watches open, and
    # Windows will not rename a directory something holds (xmip-core-path's
    # index, json-pointer and xpath, 2026-09-23). Stopped, it starts again on
    # the next git command that wants it.
    [string] $source = Join-Path $Root $From

    # A daemon that is not running answers the stop with a failure, which is
    # the state wanted.
    foreach ($tree in @($source) + @(Get-XmipNestedGit -Directory $source)) {
        Invoke-XmipGit -At $tree -Arguments @('fsmonitor--daemon', 'stop') -Test | Out-Null
    }

    if (-not (Invoke-XmipGit -At $Root -Arguments @('mv', $From, $To) -Test)) {
        # Refused by the filesystem, not by git: rename it in two steps and
        # let git read the result.
        [string] $beside = Join-Path $Root ".xmip-move-$([IO.Path]::GetRandomFileName())"

        # A rename, never Move-Item: refused a directory rename, Move-Item
        # moves file by file and stops at the first held one, leaving the
        # module in two halves (xmip-core-path, 2026-09-23). A rename either
        # happens or it does not.
        # git mv can fail after its rename, on the nested fix-up it does
        # next, and leave the directory already at its new path
        # (xmip-core-path, 2026-09-23). Then only the links are left to do.
        if (Test-Path -LiteralPath (Join-Path $Root $From) -PathType Container) {
            [IO.Directory]::Move((Join-Path $Root $From), $beside)
            [IO.Directory]::Move($beside, (Join-Path $Root $To))
        }

        Repair-XmipSubmoduleLink -Root $Root -From $From -To $To
        [string[]] $forget = @('rm', '-q', '--cached', '--ignore-unmatch', $From)
        Invoke-XmipGit -At $Root -Arguments $forget | Out-Null
    }

    # The old path is out of the index by now, by git mv or by the rm above;
    # naming it here would be a pathspec that matches nothing.
    Invoke-XmipGit -At $Root -Arguments @('add', '-A', '.gitmodules', $To) | Out-Null
}
