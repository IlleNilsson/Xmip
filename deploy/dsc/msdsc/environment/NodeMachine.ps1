#requires -PSEdition Core
#requires -Version 7.7.0

<#
    What node.resource.ps1 does for each kind: read the state, judge it and
    make it so, on Windows and on Linux. Dot-sourced by node.resource.ps1
    and by test/MsdscEnvironment.Test.ps1. The files, the openings, the
    package and the node's service are NodeFile.ps1's, NodeOpening.ps1's,
    NodePackage.ps1's and NodeService.ps1's.

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
            $state._exist = Test-NodePackage -Instance $Instance
        }
        'Slice' {
            [string] $placed = Join-Path -Path $Instance.configuration -ChildPath 'node.xmip'
            $state.access = @(Get-NodeSliceAccess -Path $placed)
            [hashtable] $activation = Get-NodeActivation -Instance $Instance
            $state.activation = $activation.said
            $state._exist = (Test-NodeSlice -Instance $Instance) -and $activation.active
        }
        'Opening' {
            # Before its package is installed the node has no program to ask:
            # absent, never refused, so a fresh machine is tested too.
            if (-not (Test-Path -LiteralPath $Instance.program -PathType Leaf)) {
                $state.ports = @()
                $state._exist = $false
                break
            }
            $state.ports = @(Get-NodeListening -Instance $Instance)
            [string] $opened = @(Get-NodeOpened -Node $Instance.node) -join ','
            $state._exist = $opened -eq ($state.ports -join ',')
        }
        'Service' {
            $state._exist = Test-NodeServiceRunning -Name $Instance.name
        }
        'Program' {
            $state = Get-NodeProgramState -Instance $Instance
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
        'Program' {
            Install-NodeProgram -Instance $Instance
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


function Get-NodeSlicePlace {
    <#
    .SYNOPSIS
    Each file of the node's slice where the node reads it, beside what it
    was shipped as: node.xmip in the configuration folder, and the
    certificate of the authority that signed it in authority/authority.pem
    there, which the node checks it by, the one its pin holds (ADR-0031,
    amendments 2026-11-06, 2026-11-07 and 2026-11-12).
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
            path    = Join-Path -Path $Instance.configuration -ChildPath 'authority/authority.pem'
            source  = $Instance.certificate
            private = $false
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

function Get-NodeActivation {
    <#
    .SYNOPSIS
    Whether the node runs the slice placed for it as its active
    configuration, and the node's words for it, as xmip-service --activation
    says (ADR-0031, amendment 2026-11-12): a correctly signed slice the node
    cannot start is refused and the node runs the last one that ran, so a
    service that started does not say the slice took. Before its package is
    installed the node has no program to ask and has run nothing: nothing is
    asked, and the package starts it by the slice.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if (-not (Test-Path -LiteralPath $Instance.program -PathType Leaf)) {
        return @{ active = $true; said = '' }
    }

    [string] $placed = Join-Path -Path $Instance.configuration -ChildPath 'node.xmip'
    [string[]] $argument = @('--configuration', $placed, '--activation')

    try {
        [string[]] $said = @(Invoke-DscProgram -Program $Instance.program -Argument $argument)
        return @{ active = $true; said = $said -join ' ' }
    }
    catch {
        return @{ active = $false; said = $_.Exception.Message }
    }
}

function Set-NodeSlice {
    <#
    .SYNOPSIS
    Put the shipped slice and its authority's certificate where the node
    reads them, make node.xmip writable by the node's account and the
    administrators alone, and restart its service where it is installed and
    a file changed, or where it does not run the slice it holds, so it runs
    by it: a changed slice takes effect when the node starts again, and one
    the node refused as it started is tried again (ADR-0031, amendment
    2026-11-12). Placed before the package, the slice is what xmip-service
    --install reads.
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

    if (-not (Test-NodeRegistered -Node $Instance.node)) {
        return
    }

    if (-not $changed -and (Get-NodeActivation -Instance $Instance).active) {
        return
    }

    # Only a node that runs is restarted, and then waited for until it is
    # ready: one that does not, as before its package is installed again, is
    # started by the package and the service after it, by the program the
    # package brings.
    [string] $name = "xmip-$($Instance.node)"
    if (-not (Test-NodeServiceActive -Name $name)) {
        return
    }
    if ($IsWindows) {
        Restart-Service -Name $name
    }
    else {
        Invoke-DscProgram -Program 'systemctl' -Argument @('restart', $name) | Out-Null
    }
    Wait-NodeReadiness -Instance $Instance
}
