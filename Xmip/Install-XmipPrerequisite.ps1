#requires -PSEdition Core
#requires -Version 7.6.5

# Dot-sourced by Xmip.psm1; the module supplies Read-XmipToml, Get-TomlValue, Get-TomlKey and
# Write-XmipStep. Import-Module ./Xmip.psm1 rather than running this file directly.

<#
.SYNOPSIS
    Reports and installs what a machine needs to run or build Xmip.

.DESCRIPTION
    prerequisite.toml declares what is needed; this decides what to do about it
    on the machine it is running on.

    PowerShell runs on Windows, Linux and macOS and the package manager differs
    on each, so nothing here assumes winget. The manifest declares a package per
    operating system and per manager, and this picks the one actually present.

    Reporting is the default. -Install acts, the same rule as Sync-XmipEstate.

    It never elevates. Where a prerequisite needs administrative rights it says
    so and prints the command, because a setup script that silently runs
    elevated installers is the thing an estate blocks.

    PowerShell itself is the one prerequisite Xmip cannot install for you: this
    module is written in it, and #requires above states the floor.

.EXAMPLE
    Import-Module ./Xmip.psm1
    Install-XmipPrerequisite -Role developer

.EXAMPLE
    Install-XmipPrerequisite -Role developer -Install -WhatIf
#>
function Install-XmipPrerequisite {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [ValidateSet('operator', 'developer', 'build')]
        [string] $Role = 'developer',

        # Report what is missing, or actually install it.
        [switch] $Install,

        [string] $ManifestPath = (Join-Path (Get-XmipRepositoryRoot) 'prerequisite.toml'),

        [switch] $IncludeOptional,

        [switch] $PassThru
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # --- bootstrap ---------------------------------------------------------
    #
    # The list is TOML and reading TOML needs PSToml, so PSToml is the one
    # prerequisite this knows about without reading the file. The module loads
    # without it — Get-XmipManifest imports it when called, not at import time —
    # so there is no circularity here.

    if (-not (Get-Module -ListAvailable -Name PSToml)) {
        if (-not $Install) {
            Write-Warning ('MISSING: PSToml, which is needed to read prerequisite.toml. ' +
                'Re-run with -Install.')
            return
        }
        if ($PSCmdlet.ShouldProcess('PSToml', 'Install from the PowerShell Gallery')) {
            Write-Host 'INSTALL: PSToml (required to read the manifest)'
            Install-Module -Name PSToml -Scope CurrentUser -Force -AcceptLicense
        }
        else {
            Write-Warning 'PSToml is missing. Nothing further can be read without it.'
            return
        }
    }
    Import-XmipToml

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Prerequisite manifest not found: $ManifestPath"
    }

    $manifest = Read-XmipToml -Path $ManifestPath
    $os = Get-XmipOperatingSystem
    $manager = Get-XmipPackageManager -OperatingSystem $os
    $roles = Resolve-XmipRole -RoleTable (Get-TomlValue -Node $manifest -Name 'role') -Name $Role
    $prerequisites = Get-TomlValue -Node $manifest -Name 'prerequisite'

    [string] $managerName = if ($manager) { $manager } else { 'no package manager found' }
    Write-XmipStep -Message "$os, $managerName, roles: $($roles -join ', ')"
    if (-not $Install) { Write-XmipStep -Message 'Reporting only. Add -Install to act.' }
    Write-Host ''

    $results = [Collections.Generic.List[object]]::new()
    function Add-XmipPrerequisiteResult {
        [CmdletBinding()]
        [OutputType([void])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Name,

            [Parameter(Mandatory = $true)]
            [string] $Status,

            [Parameter(Mandatory = $false)]
            [AllowEmptyString()]
            [string] $Detail = ''
        )

        $results.Add((New-XmipPrerequisiteResult -Name $Name -Status $Status -Detail $Detail))
    }

    foreach ($name in (Get-TomlKey -Node $prerequisites)) {
        $item = Get-TomlValue -Node $prerequisites -Name $name
        if (-not $roles.Contains([string](Get-TomlValue -Node $item -Name 'role'))) { continue }

        # Get-TomlValue, not PSObject.Properties: ConvertFrom-Toml returns an
        # IDictionary and PSObject.Properties does not enumerate its keys, so the
        # old membership tests were always false and -IncludeOptional did nothing.
        $optional = [bool](Get-TomlValue -Node $item -Name 'optional' -Default $false)
        $minimum = [string](Get-TomlValue -Node $item -Name 'minimum' -Default '')
        [string] $probe = [string](Get-TomlValue -Node $item -Name 'probe' -Default '')
        $found = Test-XmipCommand -Probe $probe

        # Some installers keep what they install off PATH — LLVM's libclang,
        # Visual Studio's link.exe — so a probe by command reported them
        # missing on a machine that builds with them (2026-09-26). A platform
        # entry may name where an installed copy sits; wildcards and
        # %VARIABLES% are expanded, and the first path that exists is enough.
        if (-not $found) {
            $bySystem = Get-TomlValue -Node $item -Name $os -Default $null
            [object[]] $present = @(
                Get-TomlValue -Node $bySystem -Name 'present_path' -Default @()
            )

            foreach ($pattern in $present) {
                [string] $expanded = [Environment]::ExpandEnvironmentVariables([string]$pattern)
                $hit = Get-Item -Path $expanded -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($hit) { $found = "present at $($hit.FullName)"; break }
            }
        }

        # Probe before honouring optional. Optional means you need not have it,
        # not that any version will do — a machine with an older .NET installed
        # would otherwise build the GUI surfaces against it and never be told.
        if ($found) {
            if (Test-XmipFloor -Name $name -Found $found -Minimum $minimum) {
                Write-Host "PRESENT: $name  ($found)"
                Add-XmipPrerequisiteResult -Name $name -Status 'present' -Detail $found
            }
            else {
                Write-Warning ("OUTDATED: $name is $found; " +
                    "Xmip requires $minimum or later. ADR-0021.")
                [string] $below = "$found < $minimum"
                Add-XmipPrerequisiteResult -Name $name -Status 'outdated' -Detail $below
            }
            continue
        }

        if ($optional -and -not $IncludeOptional) {
            Write-Host "SKIPPED OPTIONAL: $name (absent)"
            continue
        }

        # Gallery modules install by name and carry no per-system table.
        if ([string](Get-TomlValue -Node $item -Name 'source' -Default '') -eq 'psgallery') {
            $id = [string](Get-TomlValue -Node $item -Name 'id' -Default $name)
            $present = @(Get-Module -ListAvailable -Name $id)
            $good = $present -and (-not $minimum -or
                ($present | Where-Object { $_.Version -ge [version]$minimum }))

            # Declared empty and filled only when there is something to sort.
            # Casting an empty array to [version] throws, and $present is empty
            # on the MISSING path that also wants to print this.
            [string] $newest = ''

            if ($present) {
                $newest = [string](@($present.Version | Sort-Object -Descending)[0])
            }

            if ($good) {
                Write-Host "PRESENT: $name  ($newest)"
                Add-XmipPrerequisiteResult -Name $name -Status 'present' -Detail 'psgallery'
            }
            elseif (-not $Install) {
                [string] $why = 'MISSING: {0}' -f $name

                if ($present) {
                    $why = 'OUTDATED: {0} is {1}' -f $name, $newest
                }

                Write-Warning "$why; Xmip requires $minimum or later. ADR-0021."
                [string] $status = if ($present) { 'outdated' } else { 'missing' }
                Add-XmipPrerequisiteResult -Name $name -Status $status -Detail 'psgallery'
            }
            elseif ($PSCmdlet.ShouldProcess($id, 'Install from the PowerShell Gallery')) {
                Write-Host "INSTALL: $name"

                # SkipPublisherCheck because Windows ships a Microsoft-signed
                # Pester 3 whose publisher differs from the gallery's, and the
                # install is refused without it.
                [hashtable] $fromGallery = @{
                    Name                = $id
                    Scope               = 'CurrentUser'
                    Force               = $true
                    AcceptLicense       = $true
                    SkipPublisherCheck  = $true
                }

                Install-Module @fromGallery
                Add-XmipPrerequisiteResult -Name $name -Status 'installed' -Detail 'psgallery'
            }
            else {
                Add-XmipPrerequisiteResult -Name $name -Status 'would-install' -Detail 'psgallery'
            }
            continue
        }

        $spec = Get-TomlValue -Node $item -Name $os -Default $null
        if ($null -eq $spec) {
            Write-Host "NOT APPLICABLE: $name on $os"
            Add-XmipPrerequisiteResult -Name $name -Status 'not-applicable' -Detail $os
            continue
        }

        $command = [string](Get-TomlValue -Node $spec -Name 'command' -Default '')
        if ($command) {
            Write-Warning "MANUAL: $name -> $command"
            Add-XmipPrerequisiteResult -Name $name -Status 'manual' -Detail $command
            continue
        }

        [string] $package = ''

        if ($manager) {
            $package = [string](Get-TomlValue -Node $spec -Name $manager -Default '')
        }

        if (-not $package) {
            $fallback = [string](Get-TomlValue -Node $spec -Name 'fallback' -Default '')
            if ($fallback) {
                Write-Warning "MANUAL: $name is not packaged for $manager on $os. See $fallback"
                Add-XmipPrerequisiteResult -Name $name -Status 'manual' -Detail $fallback
            }
            else {
                Write-Warning "UNAVAILABLE: $name has no entry for $manager on $os"
                [string] $unpackaged = [string] $manager
                Add-XmipPrerequisiteResult -Name $name -Status 'unavailable' -Detail $unpackaged
            }
            continue
        }

        [string[]] $wingetArguments = @(
            'install'
            '--id', $package
            '--exact'
            '--accept-package-agreements'
            '--accept-source-agreements'
        )

        $arguments = switch ($manager) {
            'winget' { $wingetArguments }
            'brew' { @('install', $package) }
            'apt' { @('install', '-y', $package) }
            'dnf' { @('install', '-y', $package) }
            'zypper' { @('install', '-y', $package) }
            'pacman' { @('-S', '--noconfirm', $package) }
        }
        $override = [string](Get-TomlValue -Node $spec -Name 'override' -Default '')
        if ($override) { $arguments += @('--override', $override) }

        $line = "$manager $($arguments -join ' ')"
        $needsElevation = [bool](Get-TomlValue -Node $spec -Name 'elevation' -Default $false) -or
            ($os -eq 'linux' -and $manager -ne 'brew')

        if ($needsElevation) {
            Write-Warning "NEEDS ELEVATION: $name"
            Write-Host "    $line"
            Add-XmipPrerequisiteResult -Name $name -Status 'needs-elevation' -Detail $line
            continue
        }
        if (-not $Install) {
            Write-Warning "MISSING: $name"
            Write-Host "    $line"
            Add-XmipPrerequisiteResult -Name $name -Status 'missing' -Detail $line
            continue
        }
        if ($PSCmdlet.ShouldProcess($name, $line)) {
            Write-Host "INSTALL: $name"
            & $manager @arguments
            Add-XmipPrerequisiteResult -Name $name -Status 'installed' -Detail $line
        }
        else { Add-XmipPrerequisiteResult -Name $name -Status 'would-install' -Detail $line }
    }

    # Rust components are a second step: rustup installs the toolchain, and the
    # components come from rustup rather than from any package manager.
    $rust = Get-TomlValue -Node $prerequisites -Name 'rust' -Default $null
    if ($rust -and $roles.Contains([string](Get-TomlValue -Node $rust -Name 'role')) -and
        (Get-Command rustup -ErrorAction SilentlyContinue)) {
        # The channel, current. Every rust-toolchain.toml names the stable
        # channel, and rustup resolves that to whatever stable it last
        # installed: on 2026-09-22 this machine built on March's 1.94.1 while
        # stable was 1.98.1, and nothing said so. ADR-0021 is latest stable,
        # so an old one is outdated exactly as a version below a floor is.
        [string] $channel = [string](Get-TomlValue -Node $rust -Name 'channel' -Default '')

        if ($channel) {
            $state = Get-XmipRustChannel -Channel $channel

            if ($state.Unverifiable) {
                Write-Warning ("UNVERIFIABLE: rustup could not say whether " +
                    "$($state.Toolchain) is current.")
            }
            elseif ($state.Latest) {
                Write-Warning ("OUTDATED: $($state.Toolchain) is $($state.Current); " +
                    "$channel is $($state.Latest). ADR-0021.")
                [string] $behind = "$($state.Current) < $($state.Latest)"
                [string] $rust = "rust ($channel)"
                Add-XmipPrerequisiteResult -Name $rust -Status 'outdated' -Detail $behind

                if ($Install -and $PSCmdlet.ShouldProcess($state.Toolchain, 'rustup update')) {
                    Write-Host "INSTALL: $($state.Toolchain) $($state.Latest)"
                    rustup update $channel | Out-Host
                }
            }
            else {
                Write-Host "PRESENT: rust ($channel)  ($($state.Current))"
            }
        }

        foreach ($component in @(Get-TomlValue -Node $rust -Name 'component' -Default @())) {
            if (-not $Install) {
                Write-Host "COMPONENT: $component (rustup component add $component)"
                continue
            }
            if ($PSCmdlet.ShouldProcess("rustup component $component", 'rustup component add')) {
                Write-Host "COMPONENT: $component"
                rustup component add $component | Out-Host
            }
        }
    }

    # The event source the audit fallback writes under (ADR-0062).
    [hashtable] $source = @{
        Manifest     = $manifest
        ManifestPath = $ManifestPath
        Role         = @($roles)
        Install      = $Install
        Caller       = $PSCmdlet
    }

    foreach ($said in @(Install-XmipEventSource @source)) {
        $results.Add($said)
    }

    Write-Host ''
    $summary = $results | Group-Object status | ForEach-Object { "$($_.Name)=$($_.Count)" }
    Write-XmipStep -Message "Prerequisites: $($summary -join '  ')"

    if ($PassThru) { $results }

    # A machine below the floor is not a machine Xmip runs on. Reporting it and
    # returning success would make the floor advisory, which is exactly what
    # ADR-0021 rejects: the caller, and CI, must be able to tell from the
    # outcome and not from reading the output.
    $blocking = @($results | Where-Object { $_.status -in 'outdated', 'missing', 'unavailable' })
    if ($blocking) {
        $detail = ($blocking | ForEach-Object { "$($_.name) ($($_.status))" }) -join ', '
        [string] $refusal = "Xmip prerequisites are not satisfied: $detail. " +
            'ADR-0021: current platforms only.'

        Write-Error $refusal -ErrorAction Stop
    }
}
