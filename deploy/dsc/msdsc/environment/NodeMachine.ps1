#requires -Version 7.6

<#
    What node.resource.ps1 does for each kind: read the state, judge it and
    make it so, on Windows and on Linux. Dot-sourced by node.resource.ps1
    and by test/MsdscEnvironment.Test.ps1. The files and the openings are
    NodeFile.ps1's and NodeOpening.ps1's.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Invoke-NodeProgram {
    <#
    .SYNOPSIS
    Run a program and answer its standard output's lines; a failure throws
    with what it said.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Program,

        [Parameter()]
        [string[]] $Argument = @()
    )

    [string[]] $said = @(& $Program @Argument 2>&1 | ForEach-Object { "$_" })

    if ($LASTEXITCODE -ne 0) {
        throw "$Program $($Argument -join ' ') exited $LASTEXITCODE`: $($said -join ' ')"
    }

    return $said
}

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
            [string] $have = Get-NodeSlice -Instance $Instance
            $state._exist = $have -ceq (Get-NodeSliced -Instance $Instance)
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
        Invoke-NodeProgram -Program 'useradd' -Argument @(
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
    slices the cluster's xmip.toml already in place, and registers and
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
    Invoke-NodeProgram -Program 'dnf' -Argument @('install', '--assumeyes', $Instance.path) |
        Out-Null
}

function Get-NodeSliceFile {
    <#
    .SYNOPSIS
    Where the node reads its configuration: xmip-node.toml beside the
    cluster's xmip.toml.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $folder = Split-Path -Path $Instance.configuration
    return Join-Path -Path $folder -ChildPath 'xmip-node.toml'
}

function Get-NodeSliced {
    <#
    .SYNOPSIS
    The node's configuration as xmip-service --slice prints it from the
    cluster's xmip.toml, for the cluster the environment names.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string[]] $argument = @(
        '--configuration', $Instance.configuration, '--node', $Instance.node,
        '--cluster', $Instance.cluster, '--slice'
    )

    return (Invoke-NodeProgram -Program $Instance.program -Argument $argument) -join "`n"
}

function Get-NodeSlice {
    <#
    .SYNOPSIS
    The node's configuration as it is; empty where there is none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $file = Get-NodeSliceFile -Instance $Instance

    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        return ''
    }

    return (Get-Content -LiteralPath $file) -join "`n"
}

function Set-NodeSlice {
    <#
    .SYNOPSIS
    Write the node's slice where it reads it, and restart its service so it
    runs by it: a changed slice takes effect when the node starts again.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $file = Get-NodeSliceFile -Instance $Instance

    if (-not $PSCmdlet.ShouldProcess($file, 'Write the node''s slice and restart it')) {
        return
    }

    [string] $sliced = Get-NodeSliced -Instance $Instance
    Set-Content -LiteralPath $file -Value $sliced -Encoding utf8NoBOM

    if ($IsWindows) {
        Restart-Service -Name "xmip-$($Instance.node)"
        return
    }

    Invoke-NodeProgram -Program 'systemctl' -Argument @('restart', "xmip-$($Instance.node)") |
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
        Invoke-NodeProgram -Program 'systemctl' -Argument @('enable', '--now', $Name) | Out-Null
    }
}
