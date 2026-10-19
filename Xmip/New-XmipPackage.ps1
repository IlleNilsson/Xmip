#requires -PSEdition Core
#requires -Version 7.6.7

<#
.SYNOPSIS
    The packages a site's xmip-service goes out in (ADR-0015, amendment
    2026-10-13): the MSI and the portable archive, built on Windows; the
    .deb, .rpm and macOS .pkg, written under deploy/package and refused here.

.DESCRIPTION
    Build-XmipService -Package calls these after it has built xmip-service.
    A package holds two files, xmip-service and the runtime library; the
    layout, the starter configuration and the service's registration are
    xmip-service's own `--install`, which every package runs, so no package
    holds a copy of them. Everything made goes under .local-work/package.

    Style: doc/governance/powershell-style.md
#>


function Assert-XmipPackageBuildable {
    <#
        .SYNOPSIS
            Throws REFUSED, in words naming what is needed, for a package
            this machine does not build; before anything is built.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Package
    )

    [string] $choice = 'Builds are Windows-only for now, the owner''s choice ' +
        '(ADR-0015, amendment 2026-10-13).'

    foreach ($kind in $Package) {
        [string] $needed = switch ($kind) {
            { $_ -in 'deb', 'rpm' } {
                "A .$kind is built on Linux, x86-64 or arm64, from " +
                'deploy/package/linux/nfpm.yaml by nfpm 2.48, with cargo, libclang and a ' +
                'C++ compiler (prerequisite.toml) to build xmip-service there.'
            }
            'pkg' {
                'A .pkg is built on macOS from deploy/package/macos by pkgbuild and ' +
                'productbuild (the Xcode command line tools), signed with a Developer ID ' +
                'Installer certificate and notarized, both under an Apple Developer ' +
                'Program membership, the owner''s.'
            }
            default {
                if ($IsWindows) { '' }
                else { "-Package $kind is built on Windows." }
            }
        }

        if ($needed) {
            throw "REFUSED: -Package $kind is not built on this machine. $needed $choice"
        }
    }
}


function New-XmipPackage {
    <#
        .SYNOPSIS
            Builds the runtime library beside xmip-service, stages both, and
            makes each package asked for. Returns Kind and Path for each.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Site,

        [Parameter(Mandatory = $true)]
        [string[]] $Package,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $CargoArgument
    )

    $built = Get-XmipPackageBinary -Root $Root -CargoArgument $CargoArgument
    # The runtime's own workspace resolves its dependencies apart from the
    # root's, so its build keeps a target directory of its own: sharing one
    # lets either overwrite what the other links.
    [string] $libraryTarget = Join-Path $built.Target 'package-runtime'
    [hashtable] $library = @{
        Root            = $Root
        TargetDirectory = $libraryTarget
        CargoArgument   = $CargoArgument
    }
    Build-XmipRuntimeLibrary @library

    $cargo = Read-XmipToml -Path (Join-Path $Root 'Cargo.toml')
    $crate = Get-TomlValue -Node $cargo -Name 'package'
    [string] $version = Get-TomlValue -Node $crate -Name 'version'
    [string] $output = Join-Path $Root ".local-work/package/$version"
    [string] $stage = Join-Path $output "$Site-windows-$($built.Architecture)"
    [string] $bin = Join-Path $stage 'xmip/bin'

    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Path $bin -Force

    [string] $service = Join-Path $built.Target "$($built.Folder)/xmip-service.exe"
    [string] $runtime = Join-Path $libraryTarget "$($built.Folder)/xmip_core_runtime.dll"
    Copy-Item -LiteralPath $service, $runtime -Destination $bin

    [hashtable] $made = @{
        Root         = $Root
        Site         = $Site
        Version      = $version
        Architecture = $built.Architecture
        Stage        = $stage
        Output       = $output
    }

    foreach ($kind in $Package) {
        [string] $path = switch ($kind) {
            'msi' { New-XmipMsi @made }
            'archive' { New-XmipArchive @made }
        }
        Write-XmipStep -Message "OK: $kind $path"
        [pscustomobject] @{ Kind = $kind; Path = $path }
    }
}


function Get-XmipPackageBinary {
    <#
        .SYNOPSIS
            Where cargo puts the build its arguments ask for — the target
            directory, and under it the triple's folder with --target and the
            profile's — and the architecture it is for.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $CargoArgument
    )

    [string] $triple = ''
    [int] $at = [Array]::IndexOf($CargoArgument, '--target')

    if ($at -ge 0 -and $at + 1 -lt $CargoArgument.Count) {
        $triple = $CargoArgument[$at + 1]
    }

    [string] $architecture = if ($triple) {
        if ($triple -like 'aarch64-*') { 'arm64' } else { 'x64' }
    }
    else {
        [string] $os = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        if ($os -eq 'Arm64') { 'arm64' } else { 'x64' }
    }

    [string] $profileName = if ($CargoArgument -contains '--release') { 'release' } else { 'debug' }
    [string] $target = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR }
    else { Join-Path $Root 'target' }
    [string] $folder = if ($triple) { "$triple/$profileName" } else { $profileName }

    [pscustomobject] @{
        Target       = $target
        Folder       = $folder
        Architecture = $architecture
    }
}


function Build-XmipRuntimeLibrary {
    <#
        .SYNOPSIS
            Builds the runtime's library, the one the operator surfaces load,
            from module/platform/runtime into TargetDirectory, with the cargo
            arguments xmip-service was built with.

        .PARAMETER Subcommand
            The cargo subcommand and what it builds, `build --lib` unless
            said: iOS's remote build makes a static library with `rustc
            --lib --crate-type staticlib`, leaving the crate's own crate
            types in Cargo.toml as they are.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $TargetDirectory,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $CargoArgument,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Subcommand = @('build', '--lib')
    )

    [string] $was = $env:CARGO_TARGET_DIR
    $env:CARGO_TARGET_DIR = $TargetDirectory
    Push-Location -LiteralPath (Join-Path $Root 'module/platform/runtime')

    try {
        & cargo @Subcommand @CargoArgument 2>&1 | ForEach-Object { Write-Host "     cargo| $_" }

        if ($LASTEXITCODE -ne 0) {
            throw "FAILED: the runtime library's cargo build exited $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location

        if ($was) {
            $env:CARGO_TARGET_DIR = $was
        }
        else {
            Remove-Item -Path 'env:CARGO_TARGET_DIR' -ErrorAction SilentlyContinue
        }
    }
}


function New-XmipMsi {
    <#
        .SYNOPSIS
            Builds deploy/package/windows/Xmip.wixproj with dotnet and WiX 7
            from NuGet, and generates the winget manifest beside the MSI.
            REFUSED in words while WiX 7's EULA is not accepted on this
            machine, which is the owner's decision.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Root,
        [string] $Site,
        [string] $Version,
        [string] $Architecture,
        [string] $Stage,
        [string] $Output
    )

    [string] $project = Join-Path $Root 'deploy/package/windows/Xmip.wixproj'
    [string] $platform = if ($Architecture -eq 'arm64') { 'ARM64' } else { 'x64' }
    [string] $intermediate = (Join-Path $Stage 'obj') + [IO.Path]::DirectorySeparatorChar
    [string[]] $argument = @(
        'build', $project, '--configuration', 'Release', '--output', $Output
        "-p:Platform=$platform"
        "-p:XmipBinaryDirectory=$(Join-Path $Stage 'xmip/bin')"
        "-p:XmipVersion=$Version"
        "-p:XmipSite=$Site"
        "-p:BaseIntermediateOutputPath=$intermediate"
    )

    [string[]] $said = @(& dotnet @argument 2>&1 | ForEach-Object { "$_" })
    $said | ForEach-Object { Write-Host "    dotnet| $_" }

    if ($said -match 'WIX7015') {
        throw ('REFUSED: WiX Toolset 7 builds only once its Open Source Maintenance Fee ' +
            'EULA is accepted on this machine, and accepting it is the owner''s decision ' +
            '(ADR-0015, amendment 2026-10-13; https://docs.firegiant.com/wix/osmf/). ' +
            "To accept it, once: dotnet build $project -t:AcceptEula -p:EulaId=wix7")
    }

    if ($LASTEXITCODE -ne 0) {
        throw "FAILED: dotnet build of $project exited $LASTEXITCODE."
    }

    [string] $msi = Join-Path $Output "xmip-$Version-$Site-$platform.msi"

    if (-not (Test-Path -LiteralPath $msi)) {
        throw "FAILED: dotnet build of $project made no $msi."
    }

    [hashtable] $manifest = @{
        Msi          = $msi
        Version      = $Version
        Architecture = $Architecture
        Destination  = Join-Path $Output 'winget'
    }
    $null = New-XmipWingetManifest @manifest

    return $msi
}


function New-XmipArchive {
    <#
        .SYNOPSIS
            The portable archive: xmip/bin and the archive's README, zipped,
            for a person who wants no installer (ADR-0015 clause 5).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Root,
        [string] $Site,
        [string] $Version,
        [string] $Architecture,
        [string] $Stage,
        [string] $Output
    )

    [string] $readme = Join-Path $Root 'deploy/package/archive/README.md'
    Copy-Item -LiteralPath $readme -Destination (Join-Path $Stage 'xmip/README.md')

    [string] $zip = Join-Path $Output "xmip-$Version-$Site-windows-$Architecture.zip"
    Compress-Archive -Path (Join-Path $Stage 'xmip') -DestinationPath $zip -Force

    return $zip
}
