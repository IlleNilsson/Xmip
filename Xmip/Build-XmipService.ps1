#requires -PSEdition Core
#requires -Version 7.6.5

function Build-XmipService {
    <#
        .SYNOPSIS
            Builds xmip-service for a site: the features its target, roles
            and domains need, and nothing else.

        .DESCRIPTION
            A site, deploy/site/<name>.toml, picks one target (device, edge,
            computer, server or hosted), the node roles it serves and the
            domains it integrates; the profiles under deploy/profile say what
            each brings (ADR-0015, amendment 2026-10-01). The build carries
            the target's features, every role's (executing is receiving,
            processing and sending), each domain technology and each archive
            target the root crate links through a feature, and xmip-service's
            own required features, which its [[bin]] entry in Cargo.toml
            declares. The archive targets are the roles' that archive,
            sending and operational, each naming them in its archives; no
            domain selects one (ADR-0015, amendment 2026-10-14). A
            technology xmip-service has no feature for yet is said under
            Unlinked, not refused.

            The target vetoes. A role or a domain needing a feature the
            target refuses is REFUSED, naming the role or domain, the feature
            and the target's reason; a target that cannot run xmip-service
            at all, the device, is REFUSED with what builds for it instead:
            xmip-core alone, no_std.

            The build sets what is possible; the node's TOML picks from it at
            run time. Cargo runs at the estate root, in CARGO_TARGET_DIR when
            that is set. Returns the plan: Site, Target, Roles, Domains,
            Archives, Features, Unlinked and Command, and Package with what
            -Package made.

            -Package puts the build in the packages that carry it to a
            machine (ADR-0015, amendment 2026-10-13): it builds the runtime
            library beside xmip-service with the same cargo arguments, and
            makes each package under .local-work/package/<version>. On
            Windows, msi builds deploy/package/windows/Xmip.wixproj with
            dotnet and WiX 7, and the winget manifest beside it; archive
            zips the portable layout. deb, rpm and pkg are written under
            deploy/package and REFUSED here, in words naming what their
            build needs: builds are Windows-only for now. Each package runs
            xmip-service --install, so the layout, the starter configuration
            and the service's registration are written once, there.

            -Remote builds no site: it builds the runtime's remote build,
            --no-default-features --features remote, the library an
            operator surface follows nodes with from outside (ADR-0014,
            amendment 2026-10-14). Desktop is this machine's, debug, into
            .ai-interaction/target-remote, the one Xmip.Abi's tests load.
            Android is the phone host's, release, for aarch64-linux-android
            and x86_64-linux-android at API level 26 into
            .ai-interaction/target-android, linked by the Android NDK found
            under ANDROID_NDK_HOME, ANDROID_HOME or the per-user Android SDK;
            Xmip.Operations packages both. iOS is the iPhone's, release,
            only on macOS and REFUSED elsewhere: a static library for
            aarch64-apple-ios and aarch64-apple-ios-sim into
            .ai-interaction/target-ios, joined by xcodebuild into the
            xmip_core_runtime.xcframework Xmip.Operations links; the
            estate's CI builds it on macOS (.github/workflows/rust.yml, job
            phone-ios). Cargo runs with -j 2, one build at a time. -WhatIf
            says the commands. Returns Platform, Triple, Path and Length per
            library and per xcframework. A landing builds Desktop and
            Android itself before the module that needs it.

        .PARAMETER Site
            A site's name under deploy/site, or the path of a site file.

        .PARAMETER CargoArgument
            Further arguments for cargo after the subcommand: --release,
            --target <triple>, --locked, --config <file>. A package is for
            the --target triple's architecture, else this machine's.

        .PARAMETER Package
            The packages to make of the build: msi, deb, rpm, pkg, archive.

        .PARAMETER Remote
            The runtime's remote builds to make instead of a site's:
            Desktop, Android, iOS.

        .EXAMPLE
            Build-XmipService -Site hospital-interface -WhatIf

            Resolves the hospital's server site and says the cargo command
            it would run, building nothing.

        .EXAMPLE
            Build-XmipService -Site factory-gateway -CargoArgument '--release'

            Builds the edge gateway's xmip-service, optimized.

        .EXAMPLE
            $arm = '--target', 'aarch64-unknown-linux-gnu'
            Build-XmipService -Site mill.toml -CargoArgument $arm

            Builds a site kept outside the estate for a 64-bit ARM Linux
            machine: the edge target's first triple.

        .EXAMPLE
            $release = '--release'
            Build-XmipService -Site personal-computer -CargoArgument $release -Package msi, archive

            Builds a person's computer's xmip-service, optimized, and makes
            its x64 MSI, winget manifest and zip under .local-work/package.

        .EXAMPLE
            Build-XmipService -Remote Android

            Builds the runtime's remote build for a phone and its emulator,
            the two libraries Xmip.Operations packages for Android.

        .EXAMPLE
            Build-XmipService -Remote iOS -WhatIf

            On macOS, says the two cargo commands and the xcodebuild command
            that make the xcframework Xmip.Operations links for an iPhone
            and its simulator, building nothing.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Site')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Site')]
        [ValidateNotNullOrEmpty()]
        [string] $Site,

        [Parameter(Mandatory = $false, ParameterSetName = 'Site')]
        [AllowEmptyCollection()]
        [string[]] $CargoArgument = @(),

        [Parameter(Mandatory = $false, ParameterSetName = 'Site')]
        [ValidateSet('msi', 'deb', 'rpm', 'pkg', 'archive')]
        [string[]] $Package = @(),

        [Parameter(Mandatory = $true, ParameterSetName = 'Remote')]
        [ValidateSet('Desktop', 'Android', 'iOS')]
        [string[]] $Remote
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    trap {
        Write-XmipAudit -Action 'Build-XmipService' -ErrorRecord $_
        break
    }

    [string] $root = Get-XmipRepositoryRoot

    if ($PSCmdlet.ParameterSetName -eq 'Remote') {
        return @(Build-XmipServiceRemote -Root $root -Remote $Remote)
    }

    $manifest = Get-XmipManifest -Path (Join-Path $root 'architecture.toml')
    [hashtable] $asked = @{
        Root          = $root
        Site          = $Site
        Manifest      = $manifest
        CargoArgument = $CargoArgument
    }
    $plan = Resolve-XmipSite @asked

    if ($Package.Count -gt 0) {
        Assert-XmipPackageBuildable -Package $Package
    }
    $plan | Add-Member -NotePropertyName Package -NotePropertyValue @()

    if ($plan.Unlinked.Count -gt 0) {
        Write-Verbose "Not linked by xmip-service yet: $($plan.Unlinked -join ', ')"
    }

    if ($PSCmdlet.ShouldProcess("site $($plan.Site)", $plan.Command)) {
        Write-XmipAudit -Action 'Build-XmipService' -Phase Begin -Property @{
            Site    = $plan.Site
            Command = $plan.Command
        }
        Invoke-XmipServiceBuild -Root $root -Argument $plan.Argument
        Write-XmipStep -Message "OK: built xmip-service for site $($plan.Site)"

        if ($Package.Count -gt 0) {
            [hashtable] $packaged = @{
                Root          = $root
                Site          = $plan.Site
                Package       = $Package
                CargoArgument = $CargoArgument
            }
            $plan.Package = @(New-XmipPackage @packaged)
        }
        Write-XmipAudit -Action 'Build-XmipService' -Phase Finished -Property @{
            Site    = $plan.Site
            Package = (@($plan.Package | ForEach-Object -MemberName Path) -join ', ')
        }
    }

    return $plan
}


function Build-XmipServiceRemote {
    <#
        .SYNOPSIS
            Build-XmipService -Remote: each platform's remote build of the
            runtime, audited, one after another; -WhatIf says the commands.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string[]] $Remote
    )

    foreach ($platform in $Remote) {
        [string] $ndk = if ($platform -eq 'Android') { Find-XmipAndroidNdk } else { '' }
        [string[]] $command = @(
            Get-XmipRemoteRuntimeCommand -Root $Root -Platform $platform -Ndk $ndk)
        [string] $what = "the runtime's remote build, $platform"

        if (-not $PSCmdlet.ShouldProcess($what, ($command -join '; '))) {
            continue
        }

        Write-XmipAudit -Action 'Build-XmipService' -Phase Begin -Property @{
            Remote = $platform
        }
        Build-XmipRemoteRuntime -Root $Root -Platform $platform
        Write-XmipStep -Message "OK: built $what"
    }
}


function Invoke-XmipServiceBuild {
    <#
        .SYNOPSIS
            Runs cargo at the estate root with a resolved site's arguments;
            FAILED in words when cargo does.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string[]] $Argument
    )

    Push-Location -LiteralPath $Root

    try {
        & cargo @Argument 2>&1 | ForEach-Object { Write-Host "     cargo| $_" }

        if ($LASTEXITCODE -ne 0) {
            throw "FAILED: cargo $($Argument -join ' ') exited $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}
