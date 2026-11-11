#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Every source file the estate holds, with production and test lines
    counted apart.

.DESCRIPTION
    There was one line counter in the estate and it lived inside
    `test/Rust.Style.Test.ps1`'s `BeforeAll`, where nothing else could reach
    it. The estate map needs the same number, and a second counter would
    disagree with the first within a week — which is the whole of ADR-0020
    clause 5. So the counter moves here and the test calls it.

    Style: doc/governance/powershell-style.md
#>

# What the estate writes, and nothing else. A language is added here when the
# estate starts writing it, not before.
[hashtable] $script:XmipSourceLanguage = @{
    '.rs'  = 'Rust'
    '.cs'  = 'C#'
    '.ps1' = 'PowerShell'
}

# Build output, fetched packages, git's own directory and the working areas.
# Nobody wrote these and they would dominate every count that included them;
# Find-XmipFile never descends into one.
[string[]] $script:XmipSourceSkip = @(
    'target', 'obj', 'node_modules', '.git', '.ai-interaction', '.ai-work',
    $script:XmipWorkName
)

# .NET's build output, skipped only beside the project that builds into it.
# Rust keeps a crate's further programs in src/bin, written by hand: skipped by
# name until 2026-11-11, the Essentials' roll and node grew past the 400-line
# gate without its reading a line of either.
[string] $script:XmipDotnetOutput = 'bin'
[string] $script:XmipDotnetProject = '*.csproj'

# The trees the estate composes into: ADR-0016. `template/` is Rust the estate
# ships and every new repository is generated from, so it is counted like the
# rest rather than treated as an example. `sdk/` is what a provider builds
# against, mounted at the root since 2026-09-24 (ADR-0061); left off this list
# it would be the one crate no style gate reads. `.src` is the root crate's own
# source, xmip-service among it (ADR-0049, amendment 2026-09-11): off this list
# until 2026-11-11, when its run.rs had reached 407 lines unmeasured.
[string[]] $script:XmipSourceRoot = @('.src', 'module', 'test', 'template', 'sdk')


function Measure-XmipSourceCode {
    <#
        .SYNOPSIS
            How many of a file's lines are production rather than test.

        .DESCRIPTION
            Rust marks the boundary inside the file — everything from the
            first `#[cfg(test)]` down is test, which is rust-style.md
            section 2 and is what the gate has always counted. PowerShell and
            C# mark it in the name instead, because the estate's rule is that
            a test sits beside the code it tests in a file of its own.

        .PARAMETER Line
            The file's lines.

        .PARAMETER Language
            What `$script:XmipSourceLanguage` called it.

        .PARAMETER Name
            The file's name, for the languages that mark tests there.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Line,

        [Parameter(Mandatory = $true)]
        [string] $Language,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($Language -ne 'Rust') {
        if ($Name -match '\.Test\.(ps1|cs)$') {
            return 0
        }

        return $Line.Count
    }

    for ([int] $index = 0; $index -lt $Line.Count; $index++) {
        if ($Line[$index] -match '^\s*#\[cfg\(test\)\]') {
            return $index
        }
    }

    return $Line.Count
}


function Find-XmipFile {
    <#
        .SYNOPSIS
            Every file under the given directories whose name matches, never
            looking inside build output or the working areas.

        .DESCRIPTION
            The estate's one walk of its own trees: the source count below,
            the landing's question whether a module holds a .NET project, the
            projects a surface builds and what a repository's build uses, and
            the tests that read every Cargo.toml or project. A directory named
            in $script:XmipSourceSkip is pruned before it is entered, and so
            is a bin beside a .NET project, which is that project's build
            output; a Rust crate's src/bin is walked. A built tree is walked
            as fast as a clean one; a link is not followed, as Get-ChildItem
            -Recurse does not. Depth first, each directory's files before its
            subdirectories, both in name order.

        .PARAMETER Path
            The directories to walk. One that does not exist is skipped.

        .PARAMETER Filter
            A file name pattern, as Get-ChildItem -Filter takes it.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Filter
    )

    foreach ($start in $Path) {
        [System.IO.DirectoryInfo] $directory = [System.IO.DirectoryInfo]::new($start)

        if ($directory.Exists) {
            Find-XmipFileBelow -Directory $directory -Filter $Filter
        }
    }
}


function Find-XmipFileBelow {
    <#
        .SYNOPSIS
            Find-XmipFile's walk of one directory.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.DirectoryInfo] $Directory,

        [Parameter(Mandatory = $true)]
        [string] $Filter
    )

    $Directory.GetFiles($Filter) | Sort-Object -Property Name

    # A directory's projects are listed only where it has a child called bin,
    # so a directory without one is read once.
    [System.IO.DirectoryInfo[]] $children = @(
        $Directory.GetDirectories() |
            Where-Object { $_.Name -notin $script:XmipSourceSkip } |
            Where-Object {
                $_.Name -ne $script:XmipDotnetOutput -or
                    $Directory.GetFiles($script:XmipDotnetProject).Count -eq 0
            } |
            Where-Object { -not $_.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint) } |
            Sort-Object -Property Name
    )

    foreach ($child in $children) {
        Find-XmipFileBelow -Directory $child -Filter $Filter
    }
}


function Get-XmipSourceFile {
    <#
        .SYNOPSIS
            Every source file under the estate's composed trees and the root
            crate's own `.src`, counted.

        .DESCRIPTION
            One object per file: where it is, what it is written in, and how
            many of its lines are production, test and both. `Path` is
            relative to the estate root and uses forward slashes, so it reads
            the same on every platform and can be compared against a mount.

            Build output is excluded, so a clean tree and a built one count
            the same: target, obj, and the bin beside a .NET project. A Rust
            crate's src/bin holds programs written by hand, and is counted.

        .PARAMETER Root
            The repository root. Defaults to the one this module was imported
            from.

        .PARAMETER Language
            Count only these languages. All of them when omitted.

        .EXAMPLE
            Get-XmipSourceFile | Sort-Object Code -Descending |
                Select-Object -First 10

        .EXAMPLE
            Get-XmipSourceFile -Language Rust |
                Measure-Object -Property Code -Sum
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string] $Root,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Rust', 'C#', 'PowerShell')]
        [string[]] $Language
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $Root = Get-XmipRepositoryRoot
    }

    [string[]] $wanted = $Language

    if ($null -eq $wanted -or $wanted.Count -eq 0) {
        $wanted = @($script:XmipSourceLanguage.Values)
    }

    [string[]] $tree = @(
        $script:XmipSourceRoot |
            ForEach-Object { Join-Path $Root $_ } |
            Where-Object { Test-Path -LiteralPath $_ }
    )

    if ($tree.Count -eq 0) {
        return
    }

    Find-XmipFile -Path $tree -Filter '*' |
        Where-Object { $script:XmipSourceLanguage.ContainsKey($_.Extension) } |
        Where-Object {
            [string] $said = $script:XmipSourceLanguage[$_.Extension]
            $said -in $wanted
        } |
        ForEach-Object {
            [string[]] $line = @(Get-Content -LiteralPath $_.FullName)
            [string] $said = $script:XmipSourceLanguage[$_.Extension]

            [int] $code = Measure-XmipSourceCode -Line $line -Language $said -Name $_.Name

            [PSCustomObject]@{
                PSTypeName = 'Xmip.SourceFile'
                Path       = [IO.Path]::GetRelativePath($Root, $_.FullName) -replace '\\', '/'
                Language   = $said
                Code       = $code
                Tests      = $line.Count - $code
                Total      = $line.Count
            }
        }
}
