#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The packages a site's xmip-service goes out in (ADR-0015, amendment
    2026-10-13): the MSI and the portable archive, built on Windows; the
    .deb and .rpm, built on Linux by nfpm; the macOS .pkg, written under
    deploy/package and refused here.

.DESCRIPTION
    Build-XmipService -Package calls these after it has built xmip-service.
    A package holds three programs, Get-XmipPackageProgram's: xmip-service,
    the runtime library and xmip, the command line, and never a cli.toml;
    the layout, the starter configuration, the command line's cli.toml and
    the service's registration are xmip-service's own `--install`, which
    every package runs, so no package holds a copy of them. Everything made
    goes under .local-work/package.

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

    foreach ($kind in $Package) {
        [string] $needed = switch ($kind) {
            { $_ -in 'deb', 'rpm' } {
                if (-not $IsLinux) {
                    "A .$kind is built on Linux, x86-64 or arm64, from " +
                    'deploy/package/linux/nfpm.yaml by nfpm 2.48, with cargo, libclang and a ' +
                    "C++ compiler ($script:XmipPrerequisiteName) to build xmip-service there."
                }
                elseif ($null -eq (Get-Command -Name nfpm -ErrorAction SilentlyContinue)) {
                    "A .$kind is made by nfpm 2.48, which is not on PATH " +
                    "($script:XmipPrerequisiteName, [prerequisite.nfpm])."
                }
            }
            'pkg' {
                'A .pkg is built on macOS from deploy/package/macos by pkgbuild and ' +
                'productbuild (the Xcode command line tools), signed with a Developer ID ' +
                'Installer certificate and notarized, both under an Apple Developer ' +
                'Program membership, the owner''s. Builds for macOS wait on the owner''s ' +
                'choice (ADR-0015, amendment 2026-10-13).'
            }
            default {
                if ($IsWindows) { '' }
                else { "-Package $kind is built on Windows." }
            }
        }

        if ($needed) {
            throw "REFUSED: -Package $kind is not built on this machine. $needed"
        }
    }
}


function New-XmipPackage {
    <#
        .SYNOPSIS
            Builds the runtime library and the command line beside
            xmip-service, stages the three, and makes each package asked
            for. Returns Kind and Path for each.
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
    [object[]] $program = @(Get-XmipPackageProgram)

    # xmip-service is built; the others in their folders, into its target
    # directory, with the cargo arguments it was built with: every crate is
    # a member of the estate's one workspace (ADR-0015, amendment 2026-11-20).
    foreach ($one in @($program | Where-Object { $_.Build.Count -gt 0 })) {
        [hashtable] $building = @{
            Root            = $Root
            Folder          = $one.Folder
            TargetDirectory = $built.Target
            Argument        = @($one.Build) + $CargoArgument
        }
        Invoke-XmipCrateBuild @building
    }

    $cargo = Read-XmipToml -Path (Join-Path $Root 'Cargo.toml')
    $crate = Get-TomlValue -Node $cargo -Name 'package'
    [string] $version = Get-TomlValue -Node $crate -Name 'version'
    [string] $output = Join-Path (Get-XmipEstateLayout -Root $Root).Package $version
    [string] $system = if ($IsWindows) { 'windows' } else { 'linux' }
    [string] $stage = Join-Path $output "$Site-$system-$($built.Architecture)"
    [string] $bin = Join-Path $stage 'xmip/bin'

    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Path $bin -Force

    # The programs alone: the command line's build copies the developer's
    # cli.toml beside it, and a package ships none.
    [string] $from = Join-Path $built.Target $built.Folder

    foreach ($one in $program) {
        Copy-Item -LiteralPath (Join-Path $from $one.File) -Destination $bin
    }

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
            { $_ -in 'deb', 'rpm' } { New-XmipLinuxPackage @made -Kind $kind }
        }
        Write-XmipStep -Message "OK: $kind $path"
        [pscustomobject] @{ Kind = $kind; Path = $path }
    }
}


function Get-XmipPackageProgram {
    <#
        .SYNOPSIS
            The three programs every package carries, and the one list of
            them: xmip-service, the runtime library the operator surfaces
            load, and xmip, the command line. Each as System names its File,
            with the Folder of the estate cargo builds it in and what cargo
            Builds there.

        .DESCRIPTION
            xmip-service is built at the estate root by Build-XmipService
            before any package, so nothing is built for it here. The runtime
            library and the command line are members of the estate's one
            workspace and build in their folders into the same target
            directory (Invoke-XmipCrateBuild).

        .PARAMETER System
            windows, linux or macos: this machine's unless said.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('windows', 'linux', 'macos')]
        [string] $System = $(
            if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'macos' } else { 'linux' })
    )

    [string] $program = if ($System -eq 'windows') { '.exe' } else { '' }
    [string] $library = switch ($System) {
        'windows' { 'xmip_core_operate.dll' }
        'macos' { 'libxmip_core_operate.dylib' }
        default { 'libxmip_core_operate.so' }
    }

    [pscustomobject] @{
        Kind   = 'Service'
        File   = "xmip-service$program"
        Folder = '.'
        Build  = @()
    }
    [pscustomobject] @{
        Kind   = 'Library'
        File   = $library
        Folder = 'module/core/operation/operate'
        Build  = @('build', '--lib')
    }
    [pscustomobject] @{
        Kind   = 'Command'
        File   = "xmip$program"
        Folder = 'module/core/operation/cli'
        Build  = @('build', '--bin', 'xmip')
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

    [pscustomobject] $built = Invoke-XmipTool -Tool dotnet -Argument $argument -Output Keep
    [string[]] $said = $built.Said
    $said | ForEach-Object { Write-Host "    dotnet| $_" }

    if ($said -match 'WIX7015') {
        throw ('REFUSED: WiX Toolset 7 builds only once its Open Source Maintenance Fee ' +
            'EULA is accepted on this machine, and accepting it is the owner''s decision ' +
            '(ADR-0015, amendment 2026-10-13; https://docs.firegiant.com/wix/osmf/). ' +
            "To accept it, once: dotnet build $project -t:AcceptEula -p:EulaId=wix7")
    }

    if (-not $built.Passed) {
        throw "FAILED: dotnet build of $project."
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


function New-XmipLinuxPackage {
    <#
        .SYNOPSIS
            The .deb or the .rpm: deploy/package/linux/nfpm.yaml made by nfpm
            from the staged xmip/bin, the root crate's version, for amd64 or
            arm64, nfpm's names for x86-64 and arm64. Its scripts are named
            relative to that folder, so nfpm runs there.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Root,
        [string] $Site,
        [string] $Version,
        [string] $Architecture,
        [string] $Stage,
        [string] $Output,

        [Parameter(Mandatory = $true)]
        [ValidateSet('deb', 'rpm')]
        [string] $Kind
    )

    [string] $arch = if ($Architecture -eq 'arm64') { 'arm64' } else { 'amd64' }
    [string] $package = Join-Path $Output "xmip-$Version-$Site-linux-$Architecture.$Kind"
    [hashtable] $given = @{
        XMIP_BINARY_DIRECTORY = Join-Path $Stage 'xmip/bin'
        XMIP_VERSION          = $Version
        XMIP_ARCH             = $arch
    }
    [hashtable] $was = @{}
    foreach ($name in $given.Keys) {
        $was[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $given[$name])
    }
    Push-Location -LiteralPath (Join-Path $Root 'deploy/package/linux')
    try {
        [string[]] $nfpm = @('package', '--config', 'nfpm.yaml', '--packager', $Kind, '--target',
            $package)
        [string[]] $said = @(& nfpm @nfpm 2>&1)
        $said | ForEach-Object { Write-Host "      nfpm| $_" }
        if ($LASTEXITCODE -ne 0) {
            throw "FAILED: nfpm package --packager $Kind exited $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
        foreach ($name in $given.Keys) {
            [Environment]::SetEnvironmentVariable($name, $was[$name])
        }
    }

    return $package
}
