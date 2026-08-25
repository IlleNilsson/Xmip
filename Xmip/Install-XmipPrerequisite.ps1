#requires -PSEdition Core
#requires -Version 7.6

# Dot-sourced by Xmip.psm1, which supplies Get-TomlValue, Get-TomlKey and
# Write-Step. Import-Module ./Xmip.psm1 rather than running this file directly.

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

    function Get-XmipOperatingSystem {
        if ($IsWindows) { return 'windows' }
        if ($IsMacOS) { return 'macos' }
        if ($IsLinux) { return 'linux' }
        throw 'Unrecognised operating system. Xmip tooling supports Windows, Linux and macOS.'
    }

    function Get-XmipPackageManager([string] $OperatingSystem) {
        # The first manager on PATH wins. The order is deliberate: a machine with
        # both apt and dnf is unusual, and apt is the likelier intent on such a box.
        $candidates = switch ($OperatingSystem) {
            'windows' { @('winget') }
            'macos' { @('brew') }
            'linux' { @('apt', 'dnf', 'zypper', 'pacman') }
        }
        foreach ($candidate in $candidates) {
            if (Get-Command $candidate -ErrorAction SilentlyContinue) { return $candidate }
        }
        return $null
    }

    function Test-XmipCommand([string] $Probe) {
        if (-not $Probe) { return $null }
        $name = ($Probe -split '\s+')[0]
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { return $null }
        try { return (& $name --version 2>$null | Select-Object -First 1) }
        catch { return 'present' }
    }

    function Get-XmipReportedVersion {
        <#
            Extracts a comparable version from whatever a tool prints for
            --version. The shapes differ and none of them are a bare version:

                pwsh    PowerShell 7.6.5
                dotnet  11.0.100-preview.3.26xxx
                git     git version 2.45.1
                rustup  rustup 1.27.1 (28d1352db 2026-03-05)

            Returns $null when there is nothing comparable, which the caller
            must treat as unverifiable rather than as a failure.
        #>
        [CmdletBinding()]
        [OutputType([version])]
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [AllowNull()]
            [string] $Text
        )

        if ([string]::IsNullOrWhiteSpace($Text)) {
            return $null
        }

        [regex] $pattern = [regex]::new('\d+(?:\.\d+)+')
        [System.Text.RegularExpressions.Match] $match = $pattern.Match($Text)

        if ($match.Success -eq $false) {
            return $null
        }

        try {
            return [version]::Parse($match.Value)
        }
        catch {
            return $null
        }
    }

    function Test-XmipFloor {
        <#
            ADR-0021 is enforced here, not stated in a comment. A prerequisite
            that declares a minimum and reports a lower version is a failure,
            not a warning, and not something the caller can miss.

            Returns $true when the floor is satisfied or cannot be evaluated.
            Returns $false only when a version was read and is genuinely below
            the floor.
        #>
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Name,

            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [AllowNull()]
            [string] $Found,

            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string] $Minimum
        )

        if ([string]::IsNullOrWhiteSpace($Minimum)) {
            return $true
        }

        [version] $actual = Get-XmipReportedVersion -Text $Found

        if ($null -eq $actual) {
            Write-Warning "UNVERIFIABLE: $Name reports '$Found', which carries no version to compare against $Minimum."
            return $true
        }

        [version] $required = [version]::Parse($Minimum)

        if ($actual -ge $required) {
            return $true
        }

        return $false
    }

    function Resolve-XmipRole($RoleTable, [string] $Name) {
        # Roles are cumulative and declared in the manifest, not here.
        $seen = [Collections.Generic.List[string]]::new()
        function Walk([string] $current) {
            if ($seen.Contains($current)) { return }
            $seen.Add($current)
            foreach ($parent in @(Get-TomlValue (Get-TomlValue $RoleTable $current) 'include' @())) {
                if ($parent) { Walk ([string]$parent) }
            }
        }
        Walk $Name
        return $seen
    }

    # --- bootstrap ---------------------------------------------------------
    #
    # The list is TOML and reading TOML needs PSToml, so PSToml is the one
    # prerequisite this knows about without reading the file. The module loads
    # without it — Get-XmipManifest imports it when called, not at import time —
    # so there is no circularity here.

    if (-not (Get-Module -ListAvailable -Name PSToml)) {
        if (-not $Install) {
            Write-Warning 'MISSING: PSToml, which is needed to read prerequisite.toml. Re-run with -Install.'
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
    Import-Module PSToml -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Prerequisite manifest not found: $ManifestPath"
    }

    $manifest = ConvertFrom-Toml -InputObject (Get-Content -LiteralPath $ManifestPath -Raw -Encoding utf8)
    $os = Get-XmipOperatingSystem
    $manager = Get-XmipPackageManager $os
    $roles = Resolve-XmipRole (Get-TomlValue $manifest 'role') $Role
    $prerequisites = Get-TomlValue $manifest 'prerequisite'

    Write-Step "$os, $(if ($manager) { $manager } else { 'no package manager found' }), roles: $($roles -join ', ')"
    if (-not $Install) { Write-Step 'Reporting only. Add -Install to act.' }
    Write-Host ''

    $results = [Collections.Generic.List[object]]::new()
    function Record([string] $Name, [string] $Status, [string] $Detail) {
        $results.Add([pscustomobject]@{ name = $Name; status = $Status; detail = $Detail })
    }

    foreach ($name in (Get-TomlKey $prerequisites)) {
        $item = Get-TomlValue $prerequisites $name
        if (-not $roles.Contains([string](Get-TomlValue $item 'role'))) { continue }

        # Get-TomlValue, not PSObject.Properties: ConvertFrom-Toml returns an
        # IDictionary and PSObject.Properties does not enumerate its keys, so the
        # old membership tests were always false and -IncludeOptional did nothing.
        $optional = [bool](Get-TomlValue $item 'optional' $false)
        $minimum = [string](Get-TomlValue $item 'minimum' '')
        $found = Test-XmipCommand ([string](Get-TomlValue $item 'probe' ''))

        # Probe before honouring optional. Optional means you need not have it,
        # not that any version will do — a machine with an older .NET installed
        # would otherwise build the GUI surfaces against it and never be told.
        if ($found) {
            if (Test-XmipFloor -Name $name -Found $found -Minimum $minimum) {
                Write-Host "PRESENT: $name  ($found)"
                Record $name 'present' $found
            }
            else {
                Write-Warning "OUTDATED: $name is $found; Xmip requires $minimum or later. ADR-0021."
                Record $name 'outdated' "$found < $minimum"
            }
            continue
        }

        if ($optional -and -not $IncludeOptional) {
            Write-Host "SKIPPED OPTIONAL: $name (absent)"
            continue
        }

        # Gallery modules install by name and carry no per-system table.
        if ([string](Get-TomlValue $item 'source' '') -eq 'psgallery') {
            $id = [string](Get-TomlValue $item 'id' $name)
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
                Record $name 'present' 'psgallery'
            }
            elseif (-not $Install) {
                [string] $why = 'MISSING: {0}' -f $name

                if ($present) {
                    $why = 'OUTDATED: {0} is {1}' -f $name, $newest
                }

                Write-Warning "$why; Xmip requires $minimum or later. ADR-0021."
                Record $name $(if ($present) { 'outdated' } else { 'missing' }) 'psgallery'
            }
            elseif ($PSCmdlet.ShouldProcess($id, 'Install from the PowerShell Gallery')) {
                Write-Host "INSTALL: $name"

                # SkipPublisherCheck because Windows ships a Microsoft-signed
                # Pester 3 whose publisher differs from the gallery's, and the
                # install is refused without it.
                [hashtable] $install = @{
                    Name                = $id
                    Scope               = 'CurrentUser'
                    Force               = $true
                    AcceptLicense       = $true
                    SkipPublisherCheck  = $true
                }

                Install-Module @install
                Record -Name $name -Status 'installed' -Detail 'psgallery'
            }
            else { Record $name 'would-install' 'psgallery' }
            continue
        }

        $spec = Get-TomlValue $item $os $null
        if ($null -eq $spec) {
            Write-Host "NOT APPLICABLE: $name on $os"
            Record $name 'not-applicable' $os
            continue
        }

        $command = [string](Get-TomlValue $spec 'command' '')
        if ($command) {
            Write-Warning "MANUAL: $name -> $command"
            Record $name 'manual' $command
            continue
        }

        $package = if ($manager) { [string](Get-TomlValue $spec $manager '') } else { '' }
        if (-not $package) {
            $fallback = [string](Get-TomlValue $spec 'fallback' '')
            if ($fallback) {
                Write-Warning "MANUAL: $name is not packaged for $manager on $os. See $fallback"
                Record $name 'manual' $fallback
            }
            else {
                Write-Warning "UNAVAILABLE: $name has no entry for $manager on $os"
                Record $name 'unavailable' ([string]$manager)
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
        $override = [string](Get-TomlValue $spec 'override' '')
        if ($override) { $arguments += @('--override', $override) }

        $line = "$manager $($arguments -join ' ')"
        $needsElevation = [bool](Get-TomlValue $spec 'elevation' $false) -or
            ($os -eq 'linux' -and $manager -ne 'brew')

        if ($needsElevation) {
            Write-Warning "NEEDS ELEVATION: $name"
            Write-Host "    $line"
            Record $name 'needs-elevation' $line
            continue
        }
        if (-not $Install) {
            Write-Warning "MISSING: $name"
            Write-Host "    $line"
            Record $name 'missing' $line
            continue
        }
        if ($PSCmdlet.ShouldProcess($name, $line)) {
            Write-Host "INSTALL: $name"
            & $manager @arguments
            Record $name 'installed' $line
        }
        else { Record $name 'would-install' $line }
    }

    # Rust components are a second step: rustup installs the toolchain, and the
    # components come from rustup rather than from any package manager.
    $rust = Get-TomlValue $prerequisites 'rust' $null
    if ($rust -and $roles.Contains([string](Get-TomlValue $rust 'role')) -and
        (Get-Command rustup -ErrorAction SilentlyContinue)) {
        foreach ($component in @(Get-TomlValue $rust 'component' @())) {
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

    Write-Host ''
    $summary = $results | Group-Object status | ForEach-Object { "$($_.Name)=$($_.Count)" }
    Write-Step "Prerequisites: $($summary -join '  ')"

    if ($PassThru) { $results }

    # A machine below the floor is not a machine Xmip runs on. Reporting it and
    # returning success would make the floor advisory, which is exactly what
    # ADR-0021 rejects: the caller, and CI, must be able to tell from the
    # outcome and not from reading the output.
    $blocking = @($results | Where-Object { $_.status -in 'outdated', 'missing', 'unavailable' })
    if ($blocking) {
        $detail = ($blocking | ForEach-Object { "$($_.name) ($($_.status))" }) -join ', '
        Write-Error "Xmip prerequisites are not satisfied: $detail. ADR-0021: current platforms only." -ErrorAction Stop
    }
}
