#requires -PSEdition Core
#requires -Version 7.6.7

<#
.SYNOPSIS
    A tool shipped as a release archive, fetched, verified and unpacked for
    Install-XmipPrerequisite: no package manager, and no Node.js.

.DESCRIPTION
    prerequisite.toml's [archive.<name>] tables: a version, and per
    operating system and architecture (windows-x64, linux-arm64, ...) the
    release asset's url, its SHA-256 and the program inside it. The archive
    is unpacked under .local-work/tool/<name>/<version>, device-local state
    (CONTRIBUTING, The working area), and found there by whoever runs the
    tool, never put on PATH. An archive whose digest is not the one the
    manifest states is refused and deleted, and nothing is unpacked.

    The first is TypeScript's native compiler, which builds the VS Code
    extension's shell (the owner, 2026-10-22; ADR-0014, amendment
    2026-10-22).

    Style: doc/governance/powershell-style.md
#>


function Get-XmipArchiveTool {
    <#
        .SYNOPSIS
            Where the archived tool `Name` is kept on this machine, the asset
            this platform takes, and whether the tool is there.

        .PARAMETER Root
            The estate root, holding prerequisite.toml.

        .PARAMETER Name
            The tool's key under [archive], such as typescript.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    Import-XmipToml
    $manifest = Read-XmipToml -Path (Join-Path -Path $Root -ChildPath 'prerequisite.toml')
    $archives = Get-TomlValue -Node $manifest -Name 'archive' -Default $null
    $tool = Get-TomlValue -Node $archives -Name $Name -Default $null

    if ($null -eq $tool) {
        throw "prerequisite.toml declares no [archive.$Name]."
    }

    [string] $architecture =
        [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
    [string] $platform = "$(Get-XmipOperatingSystem)-$architecture"
    $asset = Get-TomlValue -Node $tool -Name $platform -Default $null
    [string] $version = [string](Get-TomlValue -Node $tool -Name 'version')
    [string] $directory = Join-Path -Path $Root -ChildPath ".local-work/tool/$Name/$version"
    [string] $executable = ''

    if ($null -ne $asset) {
        [string] $inside = [string](Get-TomlValue -Node $asset -Name 'executable')
        $executable = Join-Path -Path $directory -ChildPath $inside
    }

    return [pscustomobject]@{
        Name       = $Name
        Version    = $version
        Platform   = $platform
        Optional   = [bool](Get-TomlValue -Node $tool -Name 'optional' -Default $false)
        Role       = [string](Get-TomlValue -Node $tool -Name 'role')
        Url        = if ($asset) { [string](Get-TomlValue -Node $asset -Name 'url') } else { '' }
        Sha256     = if ($asset) { [string](Get-TomlValue -Node $asset -Name 'sha256') } else { '' }
        Directory  = $directory
        Executable = $executable
        Present    = $executable -ne '' -and [System.IO.File]::Exists($executable)
    }
}


function Install-XmipArchive {
    <#
        .SYNOPSIS
            Reports, and with -Install fetches, verifies and unpacks, every
            archived tool the roles take; returns one Xmip.Prerequisite line
            for each.

        .PARAMETER Manifest
            prerequisite.toml, as Read-XmipToml read it.

        .PARAMETER ManifestPath
            Its path, at the estate root.

        .PARAMETER Role
            The roles the run is for.

        .PARAMETER Install
            Fetch and unpack what is missing, rather than say how.

        .PARAMETER IncludeOptional
            Take an optional tool too; without it one absent is SKIPPED.

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

        [Parameter(Mandatory = $false)]
        [switch] $IncludeOptional,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet] $Caller
    )

    [string] $root = Split-Path -Path $ManifestPath -Parent
    $archives = Get-TomlValue -Node $Manifest -Name 'archive' -Default $null

    foreach ($key in @(Get-TomlKey -Node $archives)) {
        $tool = Get-XmipArchiveTool -Root $root -Name $key
        [string] $name = "$key ($($tool.Version))"

        if ($Role -notcontains $tool.Role) {
            continue
        }

        if ($tool.Present) {
            Write-Host "PRESENT: $name  ($($tool.Executable))"
            New-XmipPrerequisiteResult -Name $name -Status 'present' -Detail $tool.Executable
            continue
        }

        if ($tool.Url -eq '') {
            Write-Host "NOT APPLICABLE: $name on $($tool.Platform)"
            New-XmipPrerequisiteResult -Name $name -Status 'not-applicable' -Detail $tool.Platform
            continue
        }

        if ($tool.Optional -and -not $IncludeOptional) {
            Write-Host "SKIPPED OPTIONAL: $name (absent)"
            continue
        }

        [string] $line = "Install-XmipPrerequisite -Install -IncludeOptional fetches $($tool.Url)"

        if (-not $Install) {
            Write-Warning "MISSING: $name"
            Write-Host "    $line"
            New-XmipPrerequisiteResult -Name $name -Status 'missing' -Detail $line
            continue
        }

        if (-not $Caller.ShouldProcess($name, "fetch, verify and unpack $($tool.Url)")) {
            New-XmipPrerequisiteResult -Name $name -Status 'would-install' -Detail $line
            continue
        }

        Write-Host "INSTALL: $name"
        Expand-XmipArchiveTool -Tool $tool
        New-XmipPrerequisiteResult -Name $name -Status 'installed' -Detail $tool.Executable
    }
}


function Expand-XmipArchiveTool {
    <#
        .SYNOPSIS
            Fetches the tool's archive, refuses it unless its SHA-256 is the
            one the manifest states, and unpacks it where the tool is kept.

        .PARAMETER Tool
            What Get-XmipArchiveTool answered.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Tool
    )

    New-Item -ItemType Directory -Path $Tool.Directory -Force | Out-Null
    [string] $archive = Join-Path -Path $Tool.Directory -ChildPath 'archive.tgz'

    try {
        Invoke-WebRequest -Uri $Tool.Url -OutFile $archive
        [string] $digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash

        if ($digest -ne $Tool.Sha256) {
            throw ("REFUSED: $($Tool.Url) has SHA-256 $($digest.ToLower()), and " +
                "prerequisite.toml states $($Tool.Sha256); nothing was unpacked.")
        }

        # tar ships with Windows 10 and later, macOS and Linux alike.
        & tar -xzf $archive -C $Tool.Directory

        if ($LASTEXITCODE -ne 0) {
            throw "tar could not unpack $archive (exit $LASTEXITCODE)."
        }
    }
    finally {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    }

    if (-not [System.IO.File]::Exists($Tool.Executable)) {
        throw "The archive unpacked, and $($Tool.Executable) is not in it."
    }
}
