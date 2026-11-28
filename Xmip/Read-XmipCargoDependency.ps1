#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic
using namespace System.Collections.Specialized

<#
.SYNOPSIS
    The estate's one reader of a Cargo manifest's dependencies: each entry of
    every dependency table, written on its line, and the package a key names.

.DESCRIPTION
    An estate crate depends on another through the root's
    `[workspace.dependencies]` (ADR-0005, amendment 2026-11-28): a member says
    `transport = { workspace = true }`, and the root's entry under that key
    names the package, `transport = { package = "xmip-core-transport", path =
    "module/core/capability/transport" }`. So which package a member's entry
    names is read through the root, and every reader of what a crate depends
    on asks Resolve-XmipCargoPackage: the landing's order and consumers
    (Read-XmipModuleManifest), the estate map's edges (Get-XmipCargoUse), what
    a site's features link (Get-XmipRootCargo) and the workspace's writer
    (Update-XmipWorkspace).

    Read as text, a line at a time, so the writer can rewrite a line and keep
    the comment beside it; an entry is one line, as every one in the estate
    is, and a dependency written across lines or as a table of its own is
    refused in words.

    Style: doc/governance/powershell-style.md
#>


# A table's header: `[dependencies]`, `[target.'cfg(unix)'.dev-dependencies]`.
[regex] $script:XmipCargoHeader = [regex]::new(
    '^\s*\[\[?\s*(?<table>[^\[\]]+?)\s*\]\]?\s*(#.*)?$')

# The tables an entry depends from: every kind, a platform's own, and the
# workspace's, which members take with `workspace = true`.
[regex] $script:XmipCargoDependencyTable = [regex]::new(
    '^(workspace\.|target\..+\.)?(dev-|build-)?dependencies$')

# One entry on one line: its key, its inline table, and what follows it, a
# comment or nothing. A string or an array may hold a brace.
[regex] $script:XmipCargoEntry = [regex]::new(
    '^(?<indent>\s*)(?<key>[A-Za-z0-9_-]+)\s*=\s*\{(?<body>(?:"(?:[^"\\]|\\.)*"|' +
    '''[^'']*''|\[[^\]]*\]|[^}"''\[])*)\}(?<tail>\s*(#.*)?)$')

# An entry that is a version alone, `serde = "1"`.
[regex] $script:XmipCargoVersion = [regex]::new('^\s*(?<key>[A-Za-z0-9_-]+)\s*=\s*"')

# One pair of an inline table: its key and its value as written.
[regex] $script:XmipCargoPair = [regex]::new(
    '(?<key>[A-Za-z0-9_-]+)\s*=\s*(?<value>"(?:[^"\\]|\\.)*"|''[^'']*''|\[[^\]]*\]|[^,\s]+)')

# Where the root's [workspace.dependencies] was last read, so the landing's
# reading of every module reads the root once.
[hashtable] $script:XmipWorkspaceDependencyRead = @{}


function Read-XmipCargoDependency {
    <#
        .SYNOPSIS
            Each entry of every dependency table a manifest holds: Table, the
            table's name; Index and Last, its first and last line from 0;
            Key; Pair, each key of its inline table to its value as written,
            empty for a version alone; Indent and Tail, what stands before
            the key and after the table; Line, the line as written, its lines
            joined by a space where an array in it spans several.

        .DESCRIPTION
            A commented line is no entry, and nor is a dependency written as
            a table of its own (`[dependencies.x]`), which no crate of the
            estate writes. An inline table never closed throws, naming the
            file and the line.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    [string[]] $lines = [IO.File]::ReadAllLines($Path)
    [string] $table = ''

    for ([int] $index = 0; $index -lt $lines.Count; $index++) {
        [string] $line = $lines[$index]
        [string] $bare = $line.Trim()

        if ($bare.Length -eq 0 -or $bare.StartsWith('#')) {
            continue
        }

        [Text.RegularExpressions.Match] $header = $script:XmipCargoHeader.Match($line)

        if ($header.Success) {
            $table = $header.Groups['table'].Value
            continue
        }

        if (-not $script:XmipCargoDependencyTable.IsMatch($table)) {
            continue
        }

        # An array may span lines inside an inline table: windows-sys's
        # features, a line each.
        [int] $first = $index

        while ($line -match '^\s*[A-Za-z0-9_-]+\s*=\s*\{' -and
            -not $script:XmipCargoEntry.IsMatch($line)) {
            if (++$index -ge $lines.Count) {
                throw "REFUSED. ${Path}:$($first + 1) opens an inline table it never closes."
            }

            $line = "$line $($lines[$index].Trim())"
        }

        ConvertFrom-XmipCargoLine -Index $first -Last $index -Table $table -Line $line
    }
}


function ConvertFrom-XmipCargoLine {
    <#
        .SYNOPSIS
            One entry of a dependency table, from its line or its lines
            joined; nothing for a line that is not one.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [int] $Index,

        [Parameter(Mandatory)]
        [int] $Last,

        [Parameter(Mandatory)]
        [string] $Table,

        [Parameter(Mandatory)]
        [string] $Line
    )

    [Text.RegularExpressions.Match] $entry = $script:XmipCargoEntry.Match($Line)
    [OrderedDictionary] $pair = [ordered] @{}

    if ($entry.Success) {
        foreach ($match in $script:XmipCargoPair.Matches($entry.Groups['body'].Value)) {
            $pair[$match.Groups['key'].Value] = $match.Groups['value'].Value
        }

        return [pscustomobject] @{
            Table = $Table; Index = $Index; Last = $Last; Key = $entry.Groups['key'].Value
            Pair = $pair; Indent = $entry.Groups['indent'].Value
            Tail = $entry.Groups['tail'].Value; Line = $Line
        }
    }

    [Text.RegularExpressions.Match] $version = $script:XmipCargoVersion.Match($Line)

    if ($version.Success) {
        return [pscustomobject] @{
            Table = $Table; Index = $Index; Last = $Last; Key = $version.Groups['key'].Value
            Pair = $pair; Indent = ''; Tail = ''; Line = $Line
        }
    }

}



function Get-XmipCargoValue {
    <#
        .SYNOPSIS
            A pair's value without its quotes: `"xmip-core-x"` is
            xmip-core-x, `true` is true; empty when the pair is absent.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary] $Pair,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if (-not $Pair.Contains($Name)) {
        return ''
    }

    [string] $value = [string] $Pair[$Name]

    if ($value.Length -ge 2 -and $value[0] -in '"', "'" -and $value[-1] -eq $value[0]) {
        return $value.Substring(1, $value.Length - 2)
    }

    return $value
}


function Resolve-XmipCargoPackage {
    <#
        .SYNOPSIS
            The package one dependency entry names: its `package`; with
            `workspace = true`, the package the root's entry under its key
            names; otherwise its key, as cargo reads it.

        .PARAMETER Workspace
            The root's [workspace.dependencies], each key to its package
            (Get-XmipWorkspaceDependency).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Key,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.IDictionary] $Pair,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable] $Workspace
    )

    [string] $package = Get-XmipCargoValue -Pair $Pair -Name 'package'

    if ($package.Length -gt 0) {
        return $package
    }

    if ((Get-XmipCargoValue -Pair $Pair -Name 'workspace') -eq 'true' -and
        $Workspace.ContainsKey($Key)) {
        return [string] $Workspace[$Key]
    }

    return $Key
}


function Get-XmipWorkspaceDependency {
    <#
        .SYNOPSIS
            The root manifest's [workspace.dependencies], each key to the
            package it names; empty where the root has none. Read once per
            change of the file.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    [string] $path = Join-Path -Path $RepositoryRoot -ChildPath 'Cargo.toml'

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @{}
    }

    [IO.FileInfo] $file = [IO.FileInfo]::new($path)
    [string] $stamp = "$($file.LastWriteTimeUtc.Ticks)/$($file.Length)"
    $read = $script:XmipWorkspaceDependencyRead[$file.FullName]

    if ($null -ne $read -and $read.Stamp -eq $stamp) {
        return $read.Map
    }

    [hashtable] $map = @{}
    [hashtable] $none = @{}

    foreach ($entry in @(Read-XmipCargoDependency -Path $path)) {
        if ($entry.Table -eq 'workspace.dependencies') {
            [hashtable] $named = @{ Key = $entry.Key; Pair = $entry.Pair; Workspace = $none }
            $map[$entry.Key] = Resolve-XmipCargoPackage @named
        }
    }

    $script:XmipWorkspaceDependencyRead[$file.FullName] = @{ Stamp = $stamp; Map = $map }
    return $map
}
