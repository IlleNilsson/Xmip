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
            in ordinal order, the roles each declares as written, and its
            scope. The module's one reading of a cluster's nodes.

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
        Scope      = "xmip:///$name"
    }
}

function Get-XmipClusterNodeRole {
    <#
        .SYNOPSIS
            The nodes a cluster's cluster.xmip declares, in ordinal order, the
            roles each declares as written, and the Node capabilities each
            declares (ADR-0056, amendment 2026-11-24): the module's one
            reading of a cluster's [nodes].

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

    return [pscustomobject]@{ Nodes = $names; Role = $role; Capability = $capability }
}

function Read-XmipSystemTestCluster {
    <#
        .SYNOPSIS
            The nodes the System Tests' own cluster cluster.xmip declares and the
            roles each declares. It names no cluster: where it runs is the
            run's or the environment's (ADR-0028, amendment 2026-10-21).
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

function ConvertTo-XmipNodeCapability {
    <#
        .SYNOPSIS
            The Node capabilities a value of -NodeCapability says, as words:
            'online, erp-direct', 'online+erp-direct' or @('online',
            'erp-direct'). Whether each is a Node capability is the node
            crate's to say (node::Capability::node_capabilities), as the run
            reads its cluster file before anything starts.

        .PARAMETER Capability
            One node's value.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Capability
    )

    return [string[]] @(
        @($Capability) | Where-Object { $null -ne $_ } |
            ForEach-Object { ([string] $_) -split '[,+]' } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
}

function Get-XmipNodeCapabilityEntry {
    <#
        .SYNOPSIS
            Each node's Node capabilities as a run's record lists them,
            <node>=online+erp-direct, as node::Capability::declared_entry
            writes them; a node declaring none is left out.

        .PARAMETER Capability
            The Node capabilities per node, as Read-XmipTestCluster reads
            them.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowNull()]
        [System.Collections.IDictionary] $Capability
    )

    if ($null -eq $Capability) {
        return [string[]] @()
    }

    return [string[]] @(
        foreach ($node in @($Capability.Keys)) {
            [string[]] $words = @($Capability[$node] | Where-Object { $null -ne $_ })

            if ($words.Count -gt 0) {
                "$node=$($words -join '+')"
            }
        }
    )
}

function Join-XmipNodeCapability {
    <#
        .SYNOPSIS
            The Node capabilities each of -Nodes declares in a run: what
            -NodeCapability states for it, else what the System Tests' file
            declares, else none (ADR-0056, amendment 2026-11-24).

        .PARAMETER Nodes
            The run's nodes.

        .PARAMETER NodeCapability
            What -NodeCapability stated per node, or $null.

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
        [hashtable] $NodeCapability,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Declared
    )

    [hashtable] $joined = @{}

    foreach ($node in @($Nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        [string[]] $stated = @(
            if ($null -ne $NodeCapability -and $NodeCapability.ContainsKey($node)) {
                ConvertTo-XmipNodeCapability -Capability $NodeCapability[$node]
            }
            elseif ($Declared.Contains($node)) {
                $Declared[$node] | Where-Object { $null -ne $_ }
            }
        )

        if ($stated.Count -gt 0) {
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
            names declares nothing. Replaced on every run, so the file is what
            was typed this time.

        .PARAMETER Cluster
            The cluster's name, as -Cluster gave it.

        .PARAMETER Nodes
            The nodes, as -Nodes gave them; none is a cluster of none.

        .PARAMETER NodeRole
            What -NodeRole stated per node.

        .PARAMETER NodeCapability
            The Node capabilities per node, as Join-XmipNodeCapability joins
            them.

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

    [string] $file = Join-Path -Path $Path -ChildPath "$Cluster.xmip"

    if ($PSCmdlet.ShouldProcess($file, 'Write the run''s cluster file')) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-XmipConfiguration -Path $file -Value $document
    }

    return $file
}
