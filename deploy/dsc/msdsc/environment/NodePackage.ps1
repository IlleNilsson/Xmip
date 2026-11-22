#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The estate's package on a node machine (node.resource.ps1, kind
    Package): the one shipped, installed, which registers the node's
    service. On AlmaLinux the installed .rpm is compared with the shipped one
    by its header's SHA-256, and on Windows the installed xmip-service.exe
    with the portable archive's, so a build made again under the same
    version reaches the machine too.
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
        return Test-NodeArchiveInstalled -Path $Instance.path
    }

    return (Get-NodePackageDigest) -eq (Get-NodePackageDigest -Path $Instance.path)
}

function Test-NodeArchiveInstalled {
    <#
    .SYNOPSIS
    Whether the portable archive at -Path is the one installed: its
    xmip-service.exe, by SHA-256, the one in Program Files\Xmip\bin, so a
    build made again under the same version reaches the machine, as an .rpm
    is compared by its header (2026-11-21: a node was found by its service
    alone, and a new build never replaced the one there).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [string] $installed = Join-Path -Path $env:ProgramFiles -ChildPath 'Xmip\bin\xmip-service.exe'
    if (-not (Test-Path -LiteralPath $installed)) {
        return $false
    }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'xmip/bin/xmip-service.exe' } |
            Select-Object -First 1
        if ($null -eq $entry) {
            return $false
        }
        [string] $shipped = Get-NodeEntryHash -Entry $entry
    }
    finally {
        $zip.Dispose()
    }
    return $shipped -eq (Get-FileHash -LiteralPath $installed -Algorithm SHA256).Hash
}

function Get-NodeEntryHash {
    <#
    .SYNOPSIS
    The SHA-256 of what the zip entry -Entry holds, as Get-FileHash says a
    file's.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchiveEntry] $Entry
    )

    $stream = $Entry.Open()
    try {
        return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash
    }
    finally {
        $stream.Dispose()
    }
}

function Get-NodeModulesPath {
    <#
    .SYNOPSIS
    The zip of module libraries -Instance.modules names, or nothing where it
    names none; refused where it names one that is not there, so a node is
    never found current without the libraries asked of it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $path = $Instance['modules']
    if (-not $path) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "REFUSED: the module libraries $path the node names are not there."
    }
    return $path
}

function Test-NodeModules {
    <#
    .SYNOPSIS
    Whether every module library the zip -Instance.modules holds lies in the
    configuration folder as it is in the zip, by its SHA-256, so a library
    built again reaches the node whatever its length; true where the
    instance names none (2026-11-22: compared by length, a library of the
    same length was found current).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $modules = Get-NodeModulesPath -Instance $Instance
    if (-not $modules) {
        return $true
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($modules)
    try {
        foreach ($entry in $zip.Entries) {
            [string] $placed = Join-Path -Path $Instance['configuration'] -ChildPath $entry.Name
            if (-not (Test-Path -LiteralPath $placed) -or
                (Get-FileHash -LiteralPath $placed -Algorithm SHA256).Hash -ne
                (Get-NodeEntryHash -Entry $entry)) {
                return $false
            }
            # On Windows the node's account reads a library by its folder's
            # grant alone, which one inheriting nothing never has.
            if ($IsWindows -and (Get-Acl -LiteralPath $placed).AreAccessRulesProtected) {
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

    [string] $modules = Get-NodeModulesPath -Instance $Instance
    if (-not $modules) {
        return
    }
    $null = New-Item -ItemType Directory -Path $Instance['configuration'] -Force
    Expand-NodeZip -Path $modules -Destination $Instance['configuration']
    if (-not $IsWindows) {
        return
    }
    # Each library inherits its folder's access, to which xmip-service
    # --install --account adds the node's account: one unpacked inheriting
    # nothing was read by the administrators alone, and the node could not
    # open its unit (2026-11-21, the Hyper-V environment's EX1).
    $zip = [System.IO.Compression.ZipFile]::OpenRead($modules)
    try {
        foreach ($entry in $zip.Entries) {
            [string] $placed = Join-Path -Path $Instance['configuration'] -ChildPath $entry.Name
            Invoke-DscProgram -Program 'icacls.exe' -Argument @($placed, '/reset') | Out-Null
        }
    }
    finally {
        $zip.Dispose()
    }
}

function Expand-NodeZip {
    <#
    .SYNOPSIS
    A zip unpacked into a folder, each file there replaced, by .NET's own
    ZipFile: the PowerShell 7 brought to an AlmaLinux machine could not load
    Microsoft.PowerShell.Archive, so Expand-Archive was not there
    (2026-11-21, the Hyper-V environment's first Storage node).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Destination
    )

    [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $Destination, $true)
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
    # reaches its Storage nodes by name as it starts. A node running holds
    # its units open, so it is stopped first (2026-11-21, EX1 on Windows).
    Stop-NodeService -Name "xmip-$($Instance.node)" -Confirm:$false
    Install-NodeModules -Instance $Instance
    Set-NodeNamesBlock -Instance $Instance

    if ($IsWindows) {
        # The portable archive, Windows's package until the MSI is built (the
        # owner, 2026-11-21, archive now): unpacked where the MSI lays its
        # programs, Program Files\Xmip\bin, and installed by the one command
        # every package runs, over the configuration folder the MSI uses.
        [string] $root = Join-Path -Path $env:ProgramFiles -ChildPath 'Xmip'
        Expand-NodeZip -Path $Instance.path -Destination $env:TEMP
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
    # Every repository off: the package needs systemd alone, which every
    # machine has, and a machine with no network, or no name server that
    # reaches the mirrors, installs it as one that has (2026-11-21, the
    # Hyper-V environment's AlmaLinux machines).
    [string[]] $install = @('install', '--assumeyes', '--disablerepo=*', $Instance.path)
    Invoke-DscProgram -Program 'dnf' -Argument $install | Out-Null
}
