#requires -Version 7.7.0

Set-StrictMode -Version Latest

<#
    A test run's cluster, as configuration: the cluster.xmip whose [nodes] are the
    nodes a roll spawns (ADR-0056, amendment 2026-10-03: names are parameters
    and configuration). Start-XmipTest writes the run's own file from
    -Cluster, and the nodes -Nodes names or, where it names none, every node
    the System Tests' own cluster file declares, each with the roles -NodeRole
    states or that file declares (ADR-0028, amendment 2026-10-21: one file
    for one computer and for machines of their own), and names it to the
    roll in XMIP_TEST_CLUSTER — the variable every language's test fixture
    reads. The file is read and written by the runtime's one reader, through
    the operator module (Read-XmipConfiguration; ADR-0031, amendment
    2026-11-17), as every configuration Xmip runs is.

    Style: doc/governance/powershell-style.md
#>

function Get-XmipTestClusterPath {
    <#
        .SYNOPSIS
            The test cluster's cluster.xmip: the file XMIP_TEST_CLUSTER names,
            else the estate's test/cluster.xmip.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:XMIP_TEST_CLUSTER)) {
        return $env:XMIP_TEST_CLUSTER
    }

    return Join-Path -Path (Get-XmipRepositoryRoot) -ChildPath 'test/cluster.xmip'
}

function Read-XmipTestCluster {
    <#
        .SYNOPSIS
            A cluster's cluster.xmip as a test run reads it: its name, its nodes
            in ordinal order, the roles each declares as written, the Storage
            nodes [storage] nodes lists in its order, and its scope. The
            module's one reading of a cluster's nodes.

        .DESCRIPTION
            Throws where the file is not there or names no cluster_name. A
            file that declares no node is a cluster of none, which a run asked
            for with -Nodes @().

        .PARAMETER Path
            cluster.xmip.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "the cluster file $Path is not there"
    }

    $document = Read-XmipConfiguration -Path $Path
    $service = Get-TomlValue -Node $document -Name 'service'
    [string] $name = [string] (Get-TomlValue -Node $service -Name 'cluster_name')

    if (-not $name) {
        throw "the cluster file $Path names no cluster_name"
    }

    $declared = Get-XmipClusterNodeRole -Document $document

    return [pscustomobject]@{
        Path       = $Path
        Name       = $name
        Nodes      = $declared.Nodes
        Role       = $declared.Role
        Capability = $declared.Capability
        Storage    = $declared.Storage
        Scope      = "xmip:///$name"
    }
}

function Get-XmipClusterNodeRole {
    <#
        .SYNOPSIS
            The nodes a cluster's cluster.xmip declares, in ordinal order, the
            roles each declares as written, the Node capabilities each
            declares (ADR-0056, amendment 2026-11-24), and the Storage nodes
            its [storage] nodes lists, host:port, in the order it lists them,
            the configured primary first (ADR-0056, amendment 2026-10-22):
            the module's one reading of a cluster's [nodes] and [storage].

        .PARAMETER Document
            cluster.xmip, as Read-XmipConfiguration read it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Document
    )

    $declared = Get-TomlValue -Node $Document -Name 'nodes'
    [string[]] $names = @(Get-TomlKey -Node $declared)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $role = [ordered]@{}
    $capability = [ordered]@{}

    foreach ($node in $names) {
        $own = Get-TomlValue -Node $declared -Name $node
        $role[$node] = [string] (Get-TomlValue -Node $own -Name 'roles')
        $words = Get-TomlValue -Node $own -Name 'capabilities' -Default @()
        $capability[$node] = [string[]] @($words)
    }

    $storage = Get-TomlValue -Node $Document -Name 'storage'
    [string[]] $listed = @(Get-TomlValue -Node $storage -Name 'nodes' -Default @())

    return [pscustomobject]@{
        Nodes = $names; Role = $role; Capability = $capability; Storage = $listed
    }
}

function Read-XmipSystemTestCluster {
    <#
        .SYNOPSIS
            The nodes the System Tests' own cluster cluster.xmip declares, the
            roles each declares and the Storage nodes it lists. It names no
            cluster: where it runs is the run's or the environment's (ADR-0028,
            amendment 2026-10-21).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    [string] $path = (Get-XmipSystemTestLayout).Configuration
    return Get-XmipClusterNodeRole -Document (Read-XmipConfiguration -Path $path)
}

function Join-XmipNodeRole {
    <#
        .SYNOPSIS
            The roles each of -Nodes declares in a run: what -NodeRole states
            for it, else what the System Tests' file declares, else none.

        .PARAMETER Nodes
            The run's nodes.

        .PARAMETER NodeRole
            What -NodeRole stated per node, or $null.

        .PARAMETER Declared
            What the System Tests' file declares per node (Read-XmipSystemTestCluster).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Nodes = @(),

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeRole,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Declared
    )

    [hashtable] $joined = @{}

    foreach ($node in @($Nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        [string] $stated = if ($null -ne $NodeRole -and $NodeRole.ContainsKey($node)) {
            [string] $NodeRole[$node]
        }
        else {
            [string] $Declared[$node]
        }

        if ($stated -ne '') {
            $joined[$node] = $stated
        }
    }

    return $joined
}

function Write-XmipTestCluster {
    <#
        .SYNOPSIS
            Writes a run's cluster cluster.xmip from what was typed — the
            cluster, its nodes and the roles each declares — and returns its
            path.

        .DESCRIPTION
            <Path>/<Cluster>.xmip: [service] with the cluster's name, and
            one [nodes.<node>] per node, with roles where -NodeRole states
            them, in node::NodeRole's words as ConvertTo-XmipNodeRole says
            them, and capabilities where -NodeCapability states its Node
            capabilities (ADR-0056, amendment 2026-11-24). A node neither
            names declares nothing. [storage] nodes lists, in the order
            -Storage gives them, each Storage node of -Storage that is one of
            the run's nodes, so the roll's drawing says each one's place there
            and stands the configured primary first, never the first by its
            name (ADR-0052, amendment 2026-11-25); none where none is.
            Replaced on every run, so the file is what was typed this time.

        .PARAMETER Cluster
            The cluster's name, as -Cluster gave it.

        .PARAMETER Nodes
            The nodes, as -Nodes gave them; none is a cluster of none.

        .PARAMETER NodeRole
            What -NodeRole stated per node.

        .PARAMETER NodeCapability
            The Node capabilities per node, as Join-XmipNodeCapability joins
            them.

        .PARAMETER Storage
            The Storage nodes the System Tests' file lists, host:port, in its
            order (Read-XmipSystemTestCluster).

        .PARAMETER Path
            The run's directory.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Nodes = @(),

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeRole,

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeCapability,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Storage = @(),

        [Parameter(Mandatory)]
        [string] $Path
    )

    $declared = [ordered]@{}

    foreach ($node in @($Nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        [string] $roles = Get-XmipNodeRole -Name $node -NodeRole $NodeRole
        $own = [ordered]@{}

        if ($roles -ne '') {
            $own.roles = $roles
        }

        if ($null -ne $NodeCapability -and $NodeCapability.ContainsKey($node)) {
            [string[]] $words = @(ConvertTo-XmipNodeCapability -Capability $NodeCapability[$node])

            if ($words.Count -gt 0) {
                $own.capabilities = $words
            }
        }

        $declared[$node] = $own
    }

    $document = [ordered]@{
        service = [ordered]@{ name = 'xmip'; cluster_name = $Cluster }
    }

    if ($declared.Count -gt 0) {
        $document.nodes = $declared
    }

    # Each listed by its node's name, the host before the port, as
    # configure::cluster::storage_places reads it.
    [string[]] $listed = @(
        @($Storage) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Where-Object { $declared.Contains(($_ -replace ':[^:]*$', '')) }
    )

    if ($listed.Count -gt 0) {
        $document.storage = [ordered]@{ nodes = $listed }
    }

    [string] $file = Join-Path -Path $Path -ChildPath "$Cluster.xmip"

    if ($PSCmdlet.ShouldProcess($file, 'Write the run''s cluster file')) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-XmipConfiguration -Path $file -Value $document
    }

    return $file
}
