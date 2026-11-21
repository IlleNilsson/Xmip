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

    if ((Get-NodeNamesBlock) -ne (Get-NodeNamesWanted -Instance $Instance)) {
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

$script:NodeNamesBegin = "# BEGIN Xmip: the cluster's nodes"
$script:NodeNamesEnd = "# END Xmip: the cluster's nodes"

function Get-NodeHostsPath {
    <#
    .SYNOPSIS
    The machine's hosts file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($IsWindows) {
        return Join-Path -Path $env:SystemRoot -ChildPath 'System32\drivers\etc\hosts'
    }
    return '/etc/hosts'
}

function Get-NodeNamesWanted {
    <#
    .SYNOPSIS
    The lines -Instance.names asks the hosts file's Xmip block to hold.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    return (@(([string] $Instance['names']) -split "`r?`n" | Where-Object { $_.Trim() }) -join "`n")
}

function Get-NodeNamesBlock {
    <#
    .SYNOPSIS
    The lines the hosts file's Xmip block holds now; empty where it has none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    [string] $path = Get-NodeHostsPath
    [string[]] $lines = @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)
    [int] $begin = [array]::IndexOf($lines, $script:NodeNamesBegin)
    [int] $end = [array]::IndexOf($lines, $script:NodeNamesEnd)
    if ($begin -lt 0 -or $end -le $begin) {
        return ''
    }
    return (@($lines[($begin + 1)..($end - 1)] | Where-Object { $_.Trim() }) -join "`n")
}

function Set-NodeNamesBlock {
    <#
    .SYNOPSIS
    The hosts file's Xmip block written to hold -Instance.names, every other
    line of the file kept as it is; nothing where it names none.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $wanted = Get-NodeNamesWanted -Instance $Instance
    if (-not $wanted) {
        return
    }
    [string] $path = Get-NodeHostsPath
    [string[]] $lines = @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue)
    [int] $begin = [array]::IndexOf($lines, $script:NodeNamesBegin)
    [int] $end = [array]::IndexOf($lines, $script:NodeNamesEnd)
    [bool] $held = $begin -ge 0 -and $end -gt $begin
    [string[]] $kept = @(for ($at = 0; $at -lt $lines.Count; $at++) {
            if (-not ($held -and $at -ge $begin -and $at -le $end)) {
                $lines[$at]
            }
        })
    [string[]] $written = $kept + $script:NodeNamesBegin + ($wanted -split "`n") +
        $script:NodeNamesEnd
    Set-Content -LiteralPath $path -Value $written
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

    # Before the install, which starts the node: it opens its units and
    # reaches its Storage nodes by name as it starts.
    Install-NodeModules -Instance $Instance
    Set-NodeNamesBlock -Instance $Instance

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
