#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Add-XmipDeployBuild {
    <#
        .SYNOPSIS
            What each machine is given of this tree's build, under
            .local-work/package/<version>, added to the host facts: Packages,
            each node family's package and module libraries; Programs, each
            far-end family's xmip-system-test-external; and Slicer, this
            host's xmip-service, which slices and signs every node's
            configuration (ADR-0031, amendment 2026-11-06). Refused in words
            where one is not there, naming what builds it.

        .DESCRIPTION
            The packages are Build-XmipService -Site personal-computer's: the
            portable archive for a Windows node, the .rpm, built on Linux, for
            an AlmaLinux one (deploy/package/README.md), their staged
            programs beside them. A family's module libraries, which the
            cluster file's [[modules]] name, are in modules/<family>, and its
            far-end program in far-end/<family>.

        .PARAMETER Facts
            The host facts, Get-XmipDeployHost's: Packages, Programs and Slicer
            added.

        .PARAMETER Content
            The cluster file, as Read-XmipToml reads it.

        .PARAMETER Machines
            The machines, as Resolve-XmipDeployMachine resolves them.

        .PARAMETER Estate
            The estate's root.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Facts,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Content,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable[]] $Machines,

        [Parameter(Mandatory)]
        [string] $Estate
    )

    $cargo = Read-XmipToml -Path (Join-Path $Estate 'Cargo.toml')
    [string] $version = Get-TomlValue -Node (Get-TomlValue -Node $cargo -Name 'package') -Name (
        'version')
    [string] $built = Join-Path (Get-XmipEstateLayout -Root $Estate).Package $version
    [string] $site = $script:XmipDeploySite
    [string] $build = "Build-XmipService -Site $site -CargoArgument '--release'"
    [bool] $modules = @(Get-TomlValue -Node $Content -Name 'modules' -Default @()).Count -gt 0
    $Facts['Packages'] = @{}
    foreach ($family in @($Machines | Where-Object { $_.kind -eq 'node' } |
            ForEach-Object { $_.family } | Sort-Object -Unique)) {
        [string] $system = $family.ToLowerInvariant()
        [string] $kind = if ($family -eq 'Windows') { 'zip' } else { 'rpm' }
        [string] $path = Join-Path $built "xmip-$version-$site-$system-x64.$kind"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            [string] $made = if ($kind -eq 'zip') { "$build -Package archive" }
            else { "$build -Package rpm, on Linux" }
            throw "REFUSED: a $family node is installed from $path, which is not there: $made."
        }
        $Facts.Packages[$family] = @{ path = $path }
        [string] $libraries = Join-Path $built "modules/$system"
        if (Test-Path -LiteralPath $libraries -PathType Container) {
            $Facts.Packages[$family]['modules'] = $libraries
        }
        elseif ($modules) {
            throw ("REFUSED: the cluster file's [[modules]] name module libraries, which a " +
                "$family node is given from $libraries, which is not there: their libraries " +
                "built for $family.")
        }
    }
    $Facts['Programs'] = @{}
    foreach ($family in @($Machines | Where-Object { $_.kind -eq 'far end' } |
            ForEach-Object { $_.family } | Sort-Object -Unique)) {
        [string] $file = if ($family -eq 'Windows') { 'xmip-system-test-external.exe' }
        else { 'xmip-system-test-external' }
        [string] $path = Join-Path $built "far-end/$($family.ToLowerInvariant())/$file"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw ("REFUSED: a far end on a $family machine runs $path, which is not there: " +
                "the System Tests' xmip-system-test-external built for $family.")
        }
        $Facts.Programs[$family] = @{ path = $path; file = $file }
    }
    [string] $own = if ($IsWindows) { 'windows' } else { 'linux' }
    [string] $program = if ($IsWindows) { 'xmip-service.exe' } else { 'xmip-service' }
    $Facts['Slicer'] = Join-Path $built "$site-$own-x64/xmip/bin/$program"
    if (-not (Test-Path -LiteralPath $Facts.Slicer -PathType Leaf)) {
        [string] $kind = if ($IsWindows) { 'archive' } else { 'rpm' }
        throw ("REFUSED: this host slices and signs each node's configuration with " +
            "$($Facts.Slicer), which is not there: $build -Package $kind.")
    }
}
