#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Stop-XmipTestCluster {
    <#
        .SYNOPSIS
            Ends the cluster process a roll spawned, and every process that
            declared itself in that cluster, so nothing of a roll outlives it.

        .DESCRIPTION
            The nodes are asked to leave first, through the stop file they and
            their cluster share; by the time this runs the cluster should have
            nothing left to supervise. A cluster started elevated shows no path
            to a session that is not, so its name vouches for it (ADR-0053).

            What the process tree says is not enough on its own. On 2026-09-25
            a brutal roll's cluster was restarting its nodes faster than they
            could be listed: Get-XmipTestStatus said Nodes: none, Stop-XmipTest
            asked none of them to leave, and seventeen stayed running after
            their cluster ended. So after the cluster, every live process that
            declared a location inside the cluster (ADR-0053) — node, cluster
            or anything else the roll's tree started — is ended too.

        .PARAMETER Parent
            The process id of the roll whose cluster to end.

        .PARAMETER Cluster
            The cluster the roll rolls as. Empty for a roll started by hand
            under no name: then only the tree is followed.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [int] $Parent,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Cluster = ''
    )

    # Found through Get-XmipPlaygroundProcess, which judges by declaration
    # first and by name second, so a cluster whose image was rebuilt under it
    # is still found and still stopped (2026-09-19). Since 2026-09-20 its name
    # carries its cluster — xmip-playground-V1-cluster — so the kind is asked
    # for rather than the name.
    $layout = Get-XmipPlaygroundLayout

    [System.Diagnostics.Process[]] $clusters = @(
        Get-XmipPlaygroundProcess -Name 'xmip-playground-*' -Path $layout.Cluster -Kind Cluster |
            Where-Object {
                $owner = try { $_.Parent } catch { $null }
                $null -ne $owner -and $owner.Id -eq $Parent
            }
    )

    foreach ($process in $clusters) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $process.Id -Timeout 5 -ErrorAction SilentlyContinue
        Write-Verbose "stopped cluster $($process.Id) of roll $Parent"
    }

    if ([string]::IsNullOrWhiteSpace($Cluster)) {
        return
    }

    [hashtable] $declared = Read-XmipProcessDeclaration -Path (Get-XmipProcessDirectory)

    foreach ($id in @($declared.Keys)) {
        $said = $declared[$id]
        [string] $location = [string](Get-TomlValue -Node $said -Name 'location' -Default '')

        if ([int] $id -eq $Parent) {
            continue
        }

        if (-not (Test-XmipClusterLocation -Location $location -Cluster $Cluster)) {
            continue
        }

        Stop-Process -Id ([int] $id) -Force -ErrorAction SilentlyContinue
        Wait-Process -Id ([int] $id) -Timeout 5 -ErrorAction SilentlyContinue
        Write-Verbose "stopped $($said['name']) $id, declared in cluster $Cluster"
    }
}

function Test-XmipClusterLocation {
    <#
        .SYNOPSIS
            Whether a declared location is the cluster's scope root or inside
            it: xmip:///C1 and xmip:///C1/node/node-01 are C1's, and
            xmip:///C10/node/node-01 is not. Pure.

        .PARAMETER Location
            The location a process declared (ADR-0053).

        .PARAMETER Cluster
            The cluster's name, as Start-XmipTest -Cluster named it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Location,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Cluster
    )

    if ([string]::IsNullOrWhiteSpace($Location) -or [string]::IsNullOrWhiteSpace($Cluster)) {
        return $false
    }

    [string] $root = "xmip:///$Cluster"

    return $Location -eq $root -or $Location.StartsWith("$root/", [StringComparison]::Ordinal)
}
