#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

<#
.SYNOPSIS
    What a send to a test computer compares: the estate's files as Git would
    hold them.

.DESCRIPTION
    Send-XmipTestComputerEstate sends the difference between this list and
    the one it sent last; the copy there is one repository of what the
    estate holds, so the list is what Git would hold (open problem 145).

    Style: doc/governance/powershell-style.md
#>


# The one file sent that Git does not hold: the workspace's Cargo.lock, which
# the root's .gitignore keeps out of Git until the first release, so the
# computer builds the versions this one resolved, never its own resolution.
[string] $script:XmipWorkspaceLock = 'Cargo.lock'
function Get-XmipEstateSent {
    <#
        .SYNOPSIS
            What a send compares: each file Git would hold as one line, its
            path from the root with forward slashes, its size and the time it
            was written, tab between, in path order.

        .DESCRIPTION
            What Git would hold, and so what the copy there, one repository
            of it, holds too: every file a repository of the estate tracks
            (`git ls-files --recurse-submodules`), and every file the
            estate's one walk finds (Find-XmipFile) that no repository tracks
            and its own repository does not ignore (`git check-ignore`). What
            any ignore file excludes, this clone's own exclude and the
            account's included, is never sent: `.claude/` settings, `.env`,
            `logs/` (open problem 145; until 2026-11-24 every file the walk
            found was sent). One listing for the whole estate and one question
            for each repository holding an untracked file: a listing per
            repository took twenty seconds. A submodule's .git, a file naming
            where its repository is on this machine, is never sent; the
            workspace's Cargo.lock always is ($script:XmipWorkspaceLock).

        .PARAMETER Root
            The estate's root.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Root
    )

    [string] $full = [System.IO.Path]::GetFullPath($Root)
    [string[]] $listed = @(
        (Invoke-XmipGit -At $full -Arguments @(
                'ls-files', '--cached', '--recurse-submodules', '-z')) -join '' -split "`0" |
            Where-Object { $_ -ne '' }
    )
    [HashSet[string]] $held = [HashSet[string]]::new([string[]] $listed, [StringComparer]::Ordinal)
    [Dictionary[string, System.IO.FileInfo]] $found = [Dictionary[string, System.IO.FileInfo]]::new(
        [StringComparer]::Ordinal)

    foreach ($file in @(Find-XmipFile -Path $full -Filter '*')) {
        if ($file.Name -ne '.git') {
            [string] $path = [System.IO.Path]::GetRelativePath($full, $file.FullName)
            $found[$path.Replace('\', '/')] = $file
        }
    }

    [string[]] $untracked = @($found.Keys | Where-Object { -not $held.Contains($_) })

    foreach ($path in @(Get-XmipUnignoredFile -Root $full -Path $untracked)) {
        [void] $held.Add($path)
    }

    [void] $held.Add($script:XmipWorkspaceLock)
    [string[]] $sorted = @($held)
    [Array]::Sort($sorted, [StringComparer]::Ordinal)

    foreach ($path in $sorted) {
        [System.IO.FileInfo] $file = $null

        if (-not $found.TryGetValue($path, [ref] $file)) {
            $file = [System.IO.FileInfo]::new((Join-Path -Path $full -ChildPath $path))
        }

        # Tracked and deleted here, or a submodule not cloned: nothing to send.
        if ($file.Exists) {
            "$path`t$($file.Length)`t$($file.LastWriteTimeUtc.Ticks)"
        }
    }
}


function Get-XmipUnignoredFile {
    <#
        .SYNOPSIS
            The paths among -Path, untracked, that the repository holding
            each does not ignore, asked of each repository once.

        .PARAMETER Root
            The estate's root.

        .PARAMETER Path
            Untracked files, each from the root with forward slashes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Path
    )

    # Each path's repository: the nearest folder above it holding a .git, a
    # submodule's file or a repository's folder; the root's where none does.
    [Dictionary[string, List[string]]] $byRepository = [Dictionary[string, List[string]]]::new(
        [StringComparer]::Ordinal)
    [Dictionary[string, string]] $repositoryOf = [Dictionary[string, string]]::new(
        [StringComparer]::Ordinal)

    foreach ($one in $Path) {
        [string] $folder = [System.IO.Path]::GetDirectoryName($one).Replace('\', '/')
        [string] $at = $folder

        while ($at -ne '' -and -not $repositoryOf.ContainsKey($at) -and
            -not (Test-Path -LiteralPath (Join-Path -Path $Root -ChildPath "$at/.git"))) {
            $at = [System.IO.Path]::GetDirectoryName($at).Replace('\', '/')
        }

        [string] $repository = $at

        if ($repositoryOf.ContainsKey($at)) {
            $repository = $repositoryOf[$at]
        }

        $repositoryOf[$folder] = $repository

        if (-not $byRepository.ContainsKey($repository)) {
            $byRepository[$repository] = [List[string]]::new()
        }

        $byRepository[$repository].Add($one)
    }

    # Nearly every submodule holds an untracked Cargo.lock its .gitignore
    # names, so some two hundred repositories are asked: side by side, at
    # most the twelve a tool takes of the machine (Get-XmipToolParallel).
    # Each runspace has none of the module's functions: the one way the
    # module runs git is handed to it.
    [int] $parallel = Get-XmipToolParallel
    [string] $git = ${function:Invoke-XmipGit}.ToString()
    [object[]] $answered = @($byRepository.GetEnumerator() |
            ForEach-Object -ThrottleLimit $parallel -Parallel {
                ${function:Invoke-XmipGit} = $using:git
                [string] $repository = $_.Key
                [string] $at = Join-Path -Path $using:Root -ChildPath $repository
                [int] $cut = if ($repository -eq '') { 0 } else { $repository.Length + 1 }
                [string[]] $asked = @($_.Value | ForEach-Object { $_.Substring($cut) })

                # NUL between paths and after the last: PowerShell ends what it
                # pipes to a program with this system's line end, which git
                # reads as part of a path. Exit 1 says none is ignored. A
                # failure is answered, never thrown: a throw here reaches the
                # caller as no more than an error.
                [hashtable] $ask = @{
                    At = $at; Arguments = @('check-ignore', '--stdin', '-z'); Answer = @(0, 1)
                    Given = ($asked -join "`0") + "`0"
                }

                try {
                    [string] $said = @(Invoke-XmipGit @ask) -join ''
                }
                catch {
                    return [pscustomobject]@{ Fault = "$_" }
                }

                $out = [System.Collections.Generic.HashSet[string]]::new(
                    [string[]] ($said -split "`0"), [StringComparer]::Ordinal)
                $_.Value | Where-Object { -not $out.Contains($_.Substring($cut)) }
            })
    [object[]] $fault = @($answered | Where-Object { $_ -isnot [string] })

    if ($fault.Count -gt 0) {
        throw "FAILED. What Git would hold is not known: $($fault[0].Fault)."
    }

    $answered
}
