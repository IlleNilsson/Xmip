#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The estate's package on a node machine (node.resource.ps1, kind
    Package): the one shipped, installed, which registers the node's
    service. On AlmaLinux the installed .rpm is compared with the shipped one
    by its header's SHA-256, so a build made again under the same version
    reaches the machine too; the MSI is found by its service alone.
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

    if ($IsWindows) {
        return $true
    }

    return (Get-NodePackageDigest) -eq (Get-NodePackageDigest -Path $Instance.path)
}

function Install-NodePackage {
    <#
    .SYNOPSIS
    Install the estate's package, telling it the node, the cluster and the
    account: the MSI's XMIP_NODE, XMIP_CLUSTER and XMIP_ACCOUNT, the .rpm's
    variables of the same names. Either runs xmip-service --install, which
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

    if ($IsWindows) {
        [string[]] $argument = @(
            '/i', "`"$($Instance.path)`"", '/qn', '/norestart',
            "XMIP_NODE=$($Instance.node)", "XMIP_CLUSTER=$($Instance.cluster)",
            "XMIP_ACCOUNT=`"$($Instance.account)`""
        )
        [hashtable] $msiexec = @{
            FilePath     = 'msiexec.exe'
            ArgumentList = $argument
            Wait         = $true
            PassThru     = $true
        }
        $installed = Start-Process @msiexec

        # 3010: installed, a restart pending.
        if ($installed.ExitCode -notin 0, 3010) {
            throw "msiexec installing $($Instance.path) exited $($installed.ExitCode)"
        }

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
