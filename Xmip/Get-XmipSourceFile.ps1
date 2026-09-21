#requires -PSEdition Core
#requires -Version 7.6.5

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

# Build output, fetched packages and the assistant's scratch. Nobody wrote
# these and they would dominate every count that included them.
[string[]] $script:XmipSourceSkip = @(
    'target', 'bin', 'obj', 'node_modules', '.ai-interaction', '.ai-work',
    '.local-work'
)

# The trees the estate composes into: ADR-0016. `template/` is Rust the estate
# ships and every new repository is generated from, so it is counted like the
# rest rather than treated as an example.
[string[]] $script:XmipSourceRoot = @('module', 'test', 'template')


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


function Get-XmipSourceFile {
    <#
        .SYNOPSIS
            Every source file under the estate's composed trees, counted.

        .DESCRIPTION
            One object per file: where it is, what it is written in, and how
            many of its lines are production, test and both. `Path` is
            relative to the estate root and uses forward slashes, so it reads
            the same on every platform and can be compared against a mount.

            Build output is excluded, so a clean tree and a built one count
            the same.

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

    Get-ChildItem -LiteralPath $tree -Recurse -File |
        Where-Object { $script:XmipSourceLanguage.ContainsKey($_.Extension) } |
        Where-Object {
            [string] $said = $script:XmipSourceLanguage[$_.Extension]
            $said -in $wanted
        } |
        Where-Object {
            [string] $within = [IO.Path]::GetRelativePath($Root, $_.DirectoryName)
            -not ($within -split '[\\/]' | Where-Object { $_ -in $script:XmipSourceSkip })
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
