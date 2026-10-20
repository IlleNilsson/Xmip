#requires -PSEdition Core
#requires -Version 7.6.7

<#
.SYNOPSIS
    The RocksDB library every build under the estate root links, compiled
    once per version (.cargo/config.toml), for Install-XmipPrerequisite.

.DESCRIPTION
    .cargo/config.toml names ROCKSDB_LIB_DIR, .local-work/native/rocksdb/
    <version>, and links RocksDB statically from there instead of compiling
    its C++ in every build (the owner, 2026-10-05: *Compile RocksDB if there
    is a new version of it, otherwise I do not see the need*). A fresh clone
    has no .local-work, so its first cargo build failed: could not find
    native static library rocksdb (2026-10-20, the getting-started guide run
    from a clone). This says so, and with -Install compiles it once:
    ROCKSDB_COMPILE=1 cargo build in module/platform/persist/rocksdb, its
    library copied from the build's out directory to where the config names.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipNativeLibrary {
    <#
        .SYNOPSIS
            Where .cargo/config.toml links RocksDB from, the library file it
            needs there on this operating system, and whether it is there.

        .PARAMETER Root
            The estate root.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root
    )

    [string] $configuration = Join-Path -Path $Root -ChildPath '.cargo/config.toml'
    [string] $text = [System.IO.File]::ReadAllText($configuration)
    [string] $named = 'ROCKSDB_LIB_DIR\s*=\s*\{\s*value\s*=\s*"([^"]+)"'
    [System.Text.RegularExpressions.Match] $found = [regex]::Match($text, $named)

    if (-not $found.Success) {
        throw "$configuration names no ROCKSDB_LIB_DIR."
    }

    [string] $kept = $found.Groups[1].Value
    [string] $directory = Join-Path -Path $Root -ChildPath $kept
    [string] $file = if ($IsWindows) { 'rocksdb.lib' } else { 'librocksdb.a' }
    [string] $library = Join-Path -Path $directory -ChildPath $file

    return [pscustomobject]@{
        Kept      = $kept
        Version   = Split-Path -Path $kept -Leaf
        Directory = $directory
        File      = $file
        Library   = $library
        Present   = [System.IO.File]::Exists($library)
    }
}

function Install-XmipNativeLibrary {
    <#
        .SYNOPSIS
            Reports, and with -Install compiles, the RocksDB library; returns
            what it found as an Xmip.Prerequisite line, nothing where the
            roles build nothing.

        .PARAMETER Manifest
            prerequisite.toml, as Read-XmipToml read it; unused, taken as
            Install-XmipEventSource takes it.

        .PARAMETER ManifestPath
            Its path, at the estate root.

        .PARAMETER Role
            The roles the run is for: developer and build compile.

        .PARAMETER Install
            Compile it, rather than say how.

        .PARAMETER Caller
            Install-XmipPrerequisite itself, for ShouldProcess.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.Prerequisite')]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [string] $ManifestPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Role,

        [Parameter(Mandatory = $false)]
        [switch] $Install,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet] $Caller
    )

    if (-not ($Role -contains 'developer' -or $Role -contains 'build')) {
        return
    }

    [string] $root = Split-Path -Path $ManifestPath -Parent
    $native = Get-XmipNativeLibrary -Root $root
    [string] $name = "rocksdb library ($($native.Version))"

    if ($native.Present) {
        Write-Host "PRESENT: $name  ($($native.Library))"
        return New-XmipPrerequisiteResult -Name $name -Status 'present' -Detail $native.Library
    }

    [string] $line = 'Install-XmipPrerequisite -Install compiles it once, twenty minutes or more'

    if (-not $Install) {
        Write-Warning "MISSING: $name at $($native.Kept)"
        Write-Host "    $line"
        return New-XmipPrerequisiteResult -Name $name -Status 'missing' -Detail $line
    }

    if (-not $Caller.ShouldProcess($name, 'ROCKSDB_COMPILE=1 cargo build, once')) {
        return New-XmipPrerequisiteResult -Name $name -Status 'would-install' -Detail $line
    }

    Write-Host "INSTALL: $name, compiling RocksDB's C++ once"
    [string] $crate = Join-Path -Path $root -ChildPath 'module/platform/persist/rocksdb'

    # The estate's shared build directory, unless CARGO_TARGET_DIR names
    # another: the compiler's object paths are long, and cl.exe writes none
    # past 260 characters (C1083, a build directory under .local-work/native
    # in a deep clone, 2026-10-20).
    [string] $build = $env:CARGO_TARGET_DIR

    if ([string]::IsNullOrWhiteSpace($build)) {
        $build = Join-Path -Path $root -ChildPath 'target'
    }

    $saved = @($env:ROCKSDB_COMPILE, $env:CARGO_TARGET_DIR)

    try {
        $env:ROCKSDB_COMPILE = '1'
        $env:CARGO_TARGET_DIR = $build
        & cargo build --manifest-path (Join-Path -Path $crate -ChildPath 'Cargo.toml') |
            Out-Host

        if ($LASTEXITCODE -ne 0) {
            throw "RocksDB did not compile: cargo build in $crate exited $LASTEXITCODE."
        }
    }
    finally {
        $env:ROCKSDB_COMPILE, $env:CARGO_TARGET_DIR = $saved
    }

    [hashtable] $out = @{
        Path    = Join-Path -Path $build -ChildPath 'debug/build'
        Filter  = $native.File
        Recurse = $true
        File    = $true
    }
    [System.IO.FileInfo] $compiled = Get-ChildItem @out |
        Where-Object { $_.FullName -match 'librocksdb-sys' } |
        Sort-Object -Property LastWriteTimeUtc -Descending | Select-Object -First 1

    if ($null -eq $compiled) {
        throw "RocksDB compiled, and no $($native.File) is under $build."
    }

    New-Item -ItemType Directory -Path $native.Directory -Force | Out-Null
    Copy-Item -LiteralPath $compiled.FullName -Destination $native.Library
    return New-XmipPrerequisiteResult -Name $name -Status 'installed' -Detail $native.Library
}
