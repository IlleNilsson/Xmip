#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    What this machine is, what it has, whether a version is new enough, and
    which roles a role implies.

.DESCRIPTION
    Nested inside Install-XmipPrerequisite until 2026-09-22, when that function
    was 400 lines and its file 434 against the 400 the estate allows. None of
    these read anything from it; Record, which writes its results, stays.

    Style: doc/governance/powershell-style.md
#>

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
        Write-Warning ("UNVERIFIABLE: $Name reports '$Found', " +
            "which carries no version to compare against $Minimum.")
        return $true
    }

    # A floor may be written the way a person says it: Java's is "21", and
    # [version] needs two components, so [version]'21' throws. Before
    # 2026-09-19 that exception ended the whole run at the first such
    # entry, and every prerequisite after it went unreported — javac was
    # installed, and python and libudev were never reached. A floor this
    # cannot read is the manifest's defect and is said so (ADR-0055); it
    # never stops the machine being surveyed.
    [string] $floor = $Minimum.Trim()

    if ($floor -match '^\d+$') {
        $floor = "$floor.0"
    }

    [version] $required = $null

    if (-not [version]::TryParse($floor, [ref] $required)) {
        Write-Warning "UNREADABLE FLOOR: $Name declares '$Minimum', which is no version."
        return $true
    }

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
