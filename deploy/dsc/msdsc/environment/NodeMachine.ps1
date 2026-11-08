#requires -PSEdition Core
#requires -Version 7.7.0

<#
    What node.resource.ps1 does for each kind: read the state, judge it and
    make it so, on Windows and on Linux. Dot-sourced by node.resource.ps1
    and by test/MsdscEnvironment.Test.ps1. The files and the openings are
    NodeFile.ps1's and NodeOpening.ps1's.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Get-NodeMachineState {
    <#
    .SYNOPSIS
    The state of one instance of a kind: its properties as they are found,
    _exist saying whether it is there as asked.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Kind,

        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $state = $Instance.Clone()

    switch ($Kind) {
        'Account' {
            $state._exist = Test-NodeAccount -Name $Instance.name
        }
        'File' {
            $state = Get-NodeFileState -Instance $Instance
        }
        'Package' {
            $state._exist = Test-NodePackage -Node $Instance.node
        }
        'Slice' {
            [string] $placed = Join-Path -Path $Instance.configuration -ChildPath 'node.xmip'
            $state.access = @(Get-NodeSliceAccess -Path $placed)
            $state._exist = Test-NodeSlice -Instance $Instance
        }
        'Opening' {
            $state.ports = @(Get-NodeListening -Instance $Instance)
            [string] $opened = @(Get-NodeOpened -Node $Instance.node) -join ','
            $state._exist = $opened -eq ($state.ports -join ',')
        }
        'Service' {
            $state._exist = Test-NodeServiceRunning -Name $Instance.name
        }
    }

    return $state
}

function Test-NodeMachineState {
    <#
    .SYNOPSIS
    Whether what was found is what the instance asks. Every kind here asks
    one thing, that it is there as asked, so the answer is _exist.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $State
    )

    return [bool] $State._exist
}

function Set-NodeMachineState {
    <#
    .SYNOPSIS
    Make one instance as it asks; one already as asked is left alone.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Kind,

        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if ((Get-NodeMachineState -Kind $Kind -Instance $Instance)._exist) {
        return
    }

    switch ($Kind) {
        'Account' {
            New-NodeAccount -Name $Instance.name
        }
        'File' {
            Set-NodeFile -Instance $Instance
        }
        'Package' {
            Install-NodePackage -Instance $Instance
        }
        'Slice' {
            Set-NodeSlice -Instance $Instance
        }
        'Opening' {
            Set-NodeOpened -Instance $Instance
        }
        'Service' {
            Start-NodeService -Name $Instance.name
        }
    }
}

function Test-NodeAccount {
    <#
    .SYNOPSIS
    Whether the Linux account is there.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    & getent passwd $Name *> $null
    return $LASTEXITCODE -eq 0
}

function New-NodeAccount {
    <#
    .SYNOPSIS
    The node's Linux account: a system account, no login and no home of
    its own; /opt/xmip, the layout, is where it works.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Make the node''s service account')) {
        Invoke-DscProgram -Program 'useradd' -Argument @(
            '--system', '--no-create-home', '--home-dir', '/opt/xmip',
            '--shell', '/sbin/nologin', $Name
        ) | Out-Null
    }
}

function Test-NodePackage {
    <#
    .SYNOPSIS
    Whether the package has installed the node: its service, xmip-<node>,
    is registered with the machine's service manager.
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

function Install-NodePackage {
    <#
    .SYNOPSIS
    Install the estate's package, telling it the node, the cluster and the
    account: the MSI's XMIP_NODE, XMIP_CLUSTER and XMIP_ACCOUNT, the .rpm's
    variables of the same names. Either runs xmip-service --install, which
    slices cluster.xmip already in place, and registers and
    starts the node's service as that account.
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
    Invoke-DscProgram -Program 'dnf' -Argument @('install', '--assumeyes', $Instance.path) |
        Out-Null
}

function Get-NodeSlicePlace {
    <#
    .SYNOPSIS
    Each file of the node's slice where the node reads it, beside what it
    was shipped as: node.xmip in the configuration folder, and the
    certificate of the authority that signed it in authority/authority.pem
    there, which the node checks it by, the one its accepted slice pinned
    (ADR-0031, amendments 2026-11-06 and 2026-11-07).
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    return @(
        @{
            path   = Join-Path -Path $Instance.configuration -ChildPath 'node.xmip'
            source = $Instance.source
        },
        @{
            path   = Join-Path -Path $Instance.configuration -ChildPath 'authority/authority.pem'
            source = $Instance.certificate
        }
    )
}

function Test-NodeSlice {
    <#
    .SYNOPSIS
    Whether the node reads the slice it was shipped, checks it by the
    certificate it was shipped with, and alone with the administrators may
    write it (ADR-0031, amendment 2026-11-06, point 4).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable[]] $files = Get-NodeSlicePlace -Instance $Instance

    foreach ($file in $files) {
        if (-not (Get-NodeFileState -Instance $file)._exist) {
            return $false
        }
    }

    [string] $found = @(Get-NodeSliceAccess -Path $files[0].path) -join ','
    return $found -eq (@(Get-NodeSliceWanted -Account $Instance.account) -join ',')
}

function Set-NodeSlice {
    <#
    .SYNOPSIS
    Put the shipped slice and its authority's certificate where the node
    reads them, make node.xmip writable by the node's account and the
    administrators alone, and restart its service where it is installed and
    a file changed, so it runs by it: a changed slice takes effect when the
    node starts again. Placed before the package, the slice is what
    xmip-service --install reads.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable[]] $files = Get-NodeSlicePlace -Instance $Instance

    if (-not $PSCmdlet.ShouldProcess($files[0].path, 'Place the node''s slice and restart it')) {
        return
    }

    [bool] $changed = $false

    foreach ($file in $files) {
        if (-not (Get-NodeFileState -Instance $file)._exist) {
            Set-NodeFile -Instance $file -Confirm:$false
            $changed = $true
        }
    }

    Set-NodeSliceAccess -Path $files[0].path -Account $Instance.account -Confirm:$false

    if (-not $changed -or -not (Test-NodePackage -Node $Instance.node)) {
        return
    }

    if ($IsWindows) {
        Restart-Service -Name "xmip-$($Instance.node)"
        return
    }

    Invoke-DscProgram -Program 'systemctl' -Argument @('restart', "xmip-$($Instance.node)") |
        Out-Null
}
function Test-NodeServiceRunning {
    <#
    .SYNOPSIS
    Whether the node's systemd unit is active and enabled, so it starts
    with the machine. On Windows Microsoft.Windows/Service asks instead.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    & systemctl is-active --quiet $Name
    [bool] $active = $LASTEXITCODE -eq 0
    & systemctl is-enabled --quiet $Name
    return $active -and $LASTEXITCODE -eq 0
}

function Start-NodeService {
    <#
    .SYNOPSIS
    Enable the node's systemd unit and start it.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($PSCmdlet.ShouldProcess($Name, 'Enable and start')) {
        Invoke-DscProgram -Program 'systemctl' -Argument @('enable', '--now', $Name) | Out-Null
    }
}
