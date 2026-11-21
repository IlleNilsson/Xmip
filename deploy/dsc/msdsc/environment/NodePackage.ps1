#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The estate's package on a node machine (node.resource.ps1, kind
    Package): the one shipped, installed, which registers the node's
    service. On AlmaLinux the installed .rpm is compared with the shipped one
    by its header's SHA-256, so a build made again under the same version
    reaches the machine too; on Windows the node is found by its service
    alone.
    Dot-sourced by node.resource.ps1 and by test/MsdscEnvironment.Test.ps1.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Test-NodeRegistered {
    <#
    .SYNOPSIS
    Whether the node's service, xmip-<node>, is registered with the
    machine's service manager.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Node
    )

    if ($IsWindows) {
        return $null -ne (Get-Service -Name "xmip-$Node" -ErrorAction SilentlyContinue)
    }

    return Test-Path -LiteralPath "/etc/systemd/system/xmip-$Node.service"
}

function Get-NodePackageDigest {
    <#
    .SYNOPSIS
    The SHA-256 of an .rpm's header, rpm's own: of the file -Path names, or
    of the package xmip installed where -Path is not given; nothing where
    none is installed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string] $Path = ''
    )

    [string[]] $query = if ($Path) { @('-qp', $Path) } else { @('-q', 'xmip') }
    [string[]] $said = @(& rpm @query --queryformat '%{SHA256HEADER}' 2>$null)
    if ($LASTEXITCODE -ne 0) {
        return ''
    }
    return ($said -join '').Trim()
}

function Test-NodePackage {
    <#
    .SYNOPSIS
    Whether the package has installed the node: its service registered and,
    on AlmaLinux, the installed .rpm the one shipped.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if (-not (Test-NodeRegistered -Node $Instance.node)) {
        return $false
    }

    if (-not (Test-NodeModules -Instance $Instance)) {
        return $false
    }

    if ($IsWindows) {
        return $true
    }

    return (Get-NodePackageDigest) -eq (Get-NodePackageDigest -Path $Instance.path)
}

function Test-NodeModules {
    <#
    .SYNOPSIS
    Whether every module library the zip -Instance.modules holds lies in the
    configuration folder as it is in the zip, by its length; true where the
    zip holds none or the instance names none.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if (-not $Instance['modules'] -or -not (Test-Path -LiteralPath $Instance['modules'])) {
        return $true
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($Instance['modules'])
    try {
        foreach ($entry in $zip.Entries) {
            [string] $placed = Join-Path -Path $Instance['configuration'] -ChildPath $entry.Name
            if (-not (Test-Path -LiteralPath $placed) -or
                (Get-Item -LiteralPath $placed).Length -ne $entry.Length) {
                return $false
            }
        }
    }
    finally {
        $zip.Dispose()
    }
    return $true
}

function Install-NodeModules {
    <#
    .SYNOPSIS
    The module libraries of the zip -Instance.modules unpacked into the
    node's configuration folder, where each library_path is read (ADR-0066,
    amendment 2026-11-21); nothing where it names none.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if ($Instance['modules'] -and (Test-Path -LiteralPath $Instance['modules'])) {
        $null = New-Item -ItemType Directory -Path $Instance['configuration'] -Force
        [hashtable] $unpacking = @{
            LiteralPath = $Instance['modules']; DestinationPath = $Instance['configuration']
        }
        Expand-Archive @unpacking -Force
    }
}

function Install-NodePackage {
    <#
    .SYNOPSIS
    Install the estate's package, telling it the node, the cluster and the
    account: on Windows the portable archive's xmip-service, given them as
    arguments, on AlmaLinux the .rpm's XMIP_NODE, XMIP_CLUSTER and
    XMIP_ACCOUNT. Either runs xmip-service --install, which
    lays the node out by the slice already in place, and registers and
    starts the node's service as that account. An .rpm of another build is
    installed over the one there, an upgrade or the same version again.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if (-not $PSCmdlet.ShouldProcess($Instance.path, "Install node $($Instance.node)")) {
        return
    }

    # Before the install, which starts the node: it opens its units as it
    # starts.
    Install-NodeModules -Instance $Instance

    if ($IsWindows) {
        # The portable archive, Windows's package until the MSI is built (the
        # owner, 2026-11-21, archive now): unpacked where the MSI lays its
        # programs, Program Files\Xmip\bin, and installed by the one command
        # every package runs, over the configuration folder the MSI uses.
        [string] $root = Join-Path -Path $env:ProgramFiles -ChildPath 'Xmip'
        Expand-Archive -LiteralPath $Instance.path -DestinationPath $env:TEMP -Force
        [string] $unpacked = Join-Path -Path $env:TEMP -ChildPath 'xmip\bin'
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'bin') -Force
        Copy-Item -Path (Join-Path $unpacked '*') -Destination (Join-Path $root 'bin') -Force
        [string] $configuration = Join-Path -Path $env:ProgramData -ChildPath (
            'Xmip\config\cluster.xmip')
        [string[]] $argument = @(
            '--configuration', $configuration, '--node', $Instance.node,
            '--cluster', $Instance.cluster, '--account', $Instance.account, '--install'
        )
        [string] $service = Join-Path -Path $root -ChildPath 'bin\xmip-service.exe'
        Invoke-DscProgram -Program $service -Argument $argument | Out-Null

        return
    }

    $env:XMIP_NODE = $Instance.node
    $env:XMIP_CLUSTER = $Instance.cluster
    $env:XMIP_ACCOUNT = $Instance.account
    # rpm's own upgrade, the same version again included, runs the package's
    # postinstall.sh, which installs the node again and restarts it.
    if (Get-NodePackageDigest) {
        [string[]] $upgrade = @('--upgrade', '--replacepkgs', '--replacefiles', $Instance.path)
        Invoke-DscProgram -Program 'rpm' -Argument $upgrade | Out-Null
        return
    }
    Invoke-DscProgram -Program 'dnf' -Argument @('install', '--assumeyes', $Instance.path) |
        Out-Null
}
