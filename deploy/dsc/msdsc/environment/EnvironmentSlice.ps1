#requires -Version 7.6

<#
    Slice, on the machine deploying the environment: a node's configuration as
    xmip-service --slice prints it from the cluster's cluster.xmip, signed by
    the environment's authority (--authority), written into the node's folder
    as node.xmip with that authority's certificate beside it in
    authority/authority.pem: the two files the node is shipped. A node never
    slices and never holds the authority's key, so a file edited on it is
    refused there (ADR-0031, amendment 2026-11-06).

    A signature differs every time it is made, so what is compared is the
    text it signs: the slice above its [signature] table.

    Style: doc/governance/powershell-style.md
#>

function Get-EnvironmentSignedText {
    <#
    .SYNOPSIS
    A signed slice's text above its [signature] table: what its signature
    is over, the same however often it is signed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Slice
    )

    [int] $at = $Slice.IndexOf("`n[signature]`n", [StringComparison]::Ordinal)
    if ($at -lt 0) {
        return $Slice
    }
    return $Slice.Substring(0, $at + 1)
}

function Get-EnvironmentSliced {
    <#
    .SYNOPSIS
    The node's configuration as xmip-service --slice prints it from the
    cluster's cluster.xmip for the cluster the environment names, signed by
    the authority kept in the instance's authority folder; with every Receive
    Location and Send Port placed over the nodes on the Parties' far end
    where the instance gives bind and nodes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string[]] $argument = @(
        '--configuration', $Instance.configuration, '--node', $Instance.node,
        '--cluster', $Instance.cluster, '--authority', $Instance.authority
    )

    if ($Instance.Contains('bind') -and $Instance.bind) {
        $argument += @('--bind', $Instance.bind, '--nodes', $Instance.nodes)
    }

    $argument += '--slice'

    return ((Invoke-DscProgram -Program $Instance.program -Argument $argument) -join "`n") + "`n"
}

function Get-EnvironmentSliceFile {
    <#
    .SYNOPSIS
    Where the node's slice is written, and its authority's certificate:
    node.xmip and authority/authority.pem in the instance's into folder.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    return @(
        (Join-Path -Path $Instance.into -ChildPath 'node.xmip'),
        (Join-Path -Path $Instance.into -ChildPath 'authority/authority.pem')
    )
}

function Get-EnvironmentSlice {
    <#
    .SYNOPSIS
    The instance's state: _exist where its folder holds the node's slice as
    the cluster's file slices it now, signed, with the certificate of the
    authority that signs it beside it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $state = $Instance.Clone()
    [string[]] $files = Get-EnvironmentSliceFile -Instance $Instance
    [string] $slice = $files[0]
    [string] $certificate = $files[1]
    [string] $anchor = Join-Path -Path $Instance.authority -ChildPath 'authority.pem'
    [bool] $placed = (Test-Path -LiteralPath $slice -PathType Leaf) -and
        (Test-Path -LiteralPath $certificate -PathType Leaf)
    $state._exist = $false

    if ($placed) {
        [string] $have = Get-EnvironmentSignedText -Slice ([IO.File]::ReadAllText($slice))
        [string] $fresh = Get-EnvironmentSignedText -Slice (Get-EnvironmentSliced -Instance $Instance)
        [bool] $same = [IO.File]::ReadAllText($certificate) -ceq [IO.File]::ReadAllText($anchor)
        $state._exist = $same -and ($have -ceq $fresh)
    }

    return $state
}

function Set-EnvironmentSlice {
    <#
    .SYNOPSIS
    Write the node's signed slice and its authority's certificate into the
    instance's folder, for Xmip.Environment/Machine to ship.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string[]] $files = Get-EnvironmentSliceFile -Instance $Instance
    [string] $slice = $files[0]
    [string] $certificate = $files[1]

    if (-not $PSCmdlet.ShouldProcess($slice, 'Write the node''s signed slice')) {
        return
    }

    [string] $sliced = Get-EnvironmentSliced -Instance $Instance
    [string] $anchor = Join-Path -Path $Instance.authority -ChildPath 'authority.pem'
    New-Item -ItemType Directory -Force -Path (Split-Path -Path $certificate) | Out-Null
    [IO.File]::WriteAllText($certificate, [IO.File]::ReadAllText($anchor))
    [IO.File]::WriteAllText($slice, $sliced)
}
