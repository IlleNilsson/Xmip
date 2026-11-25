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

    [bool] $modules = @(Get-TomlValue -Node $Content -Name 'modules' -Default @()).Count -gt 0
    $Facts['Packages'] = @{}
    foreach ($family in @($Machines | Where-Object { $_.kind -eq 'node' } |
            ForEach-Object { $_.family } | Sort-Object -Unique)) {
        [hashtable] $built = Get-XmipBuiltProgram -Estate $Estate -Family $family
        if (-not (Test-Path -LiteralPath $built.Package -PathType Leaf)) {
            throw ("REFUSED: a $family node is installed from $($built.Package), which is not " +
                "there: $($built.Build).")
        }
        $Facts.Packages[$family] = @{ path = $built.Package }
        if (Test-Path -LiteralPath $built.Modules -PathType Container) {
            $Facts.Packages[$family]['modules'] = $built.Modules
        }
        elseif ($modules) {
            throw ("REFUSED: the cluster file's [[modules]] name module libraries, which a " +
                "$family node is given from $($built.Modules), which is not there: their " +
                "libraries built for $family.")
        }
    }
    $Facts['Programs'] = @{}
    foreach ($family in @($Machines | Where-Object { $_.kind -eq 'far end' } |
            ForEach-Object { $_.family } | Sort-Object -Unique)) {
        [string] $path = (Get-XmipBuiltProgram -Estate $Estate -Family $family).FarEnd
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw ("REFUSED: a far end on a $family machine runs $path, which is not there: " +
                "the System Tests' xmip-system-test-external built for $family.")
        }
        $Facts.Programs[$family] = @{ path = $path; file = Split-Path -Path $path -Leaf }
    }
    [string] $own = if ($IsWindows) { 'Windows' } else { 'Linux' }
    [hashtable] $slicing = Get-XmipBuiltProgram -Estate $Estate -Family $own
    $Facts['Slicer'] = $slicing.Service
    if (-not (Test-Path -LiteralPath $Facts.Slicer -PathType Leaf)) {
        throw ("REFUSED: this host slices and signs each node's configuration with " +
            "$($Facts.Slicer), which is not there: $($slicing.Build).")
    }
}

function Get-XmipBuiltProgram {
    <#
        .SYNOPSIS
            Where this tree's build under .local-work/package/<version> keeps
            what a machine of one family is given, the one place its layout
            is said: Package, the family's package; Service, the xmip-service
            the package stages; FarEnd, the System Tests' far-end program;
            Modules, the folder of the module libraries; and Build, what
            makes the package. Tests nothing.

        .DESCRIPTION
            The packages are Build-XmipService -Site personal-computer's: the
            portable archive for Windows, the .rpm, built on Linux, for an
            AlmaLinux machine, and for a container of the System Tests
            (Start-XmipSystemTestContainer); their staged programs beside them.

        .PARAMETER Estate
            The estate's root.

        .PARAMETER Family
            Windows or Linux.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [ValidateSet('Windows', 'Linux')]
        [string] $Family
    )

    $cargo = Read-XmipToml -Path (Join-Path $Estate 'Cargo.toml')
    [string] $version = Get-TomlValue -Node (Get-TomlValue -Node $cargo -Name 'package') -Name (
        'version')
    [string] $built = Join-Path (Get-XmipEstateLayout -Root $Estate).Package $version
    [string] $site = $script:XmipDeploySite
    [string] $system = $Family.ToLowerInvariant()
    [string] $suffix = if ($Family -eq 'Windows') { '.exe' } else { '' }
    [string] $kind = if ($Family -eq 'Windows') { 'zip' } else { 'rpm' }
    [string] $made = if ($Family -eq 'Windows') { 'archive' } else { 'rpm, on Linux' }
    return @{
        Package = Join-Path $built "xmip-$version-$site-$system-x64.$kind"
        Service = Join-Path $built "$site-$system-x64/xmip/bin/xmip-service$suffix"
        FarEnd  = Join-Path $built "far-end/$system/xmip-system-test-external$suffix"
        Modules = Join-Path $built "modules/$system"
        Build   = "Build-XmipService -Site $site -CargoArgument '--release' -Package $made"
    }
}
