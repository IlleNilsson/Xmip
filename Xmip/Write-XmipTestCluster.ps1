#requires -Version 7.6.5

Set-StrictMode -Version Latest

<#
    A test run's cluster, as configuration: the xmip.toml whose [nodes] are the
    nodes a roll spawns (ADR-0056, amendment 2026-10-03: names are parameters
    and configuration). Start-XmipTest writes the run's own file from -Cluster,
    -Nodes and -NodeRole, or takes the test cluster's where -Nodes was not
    given, and names it to the roll in XMIP_TEST_CLUSTER — the variable every
    language's test fixture reads.

    Style: doc/governance/powershell-style.md
#>

function Get-XmipTestClusterPath {
    <#
        .SYNOPSIS
            The test cluster's xmip.toml: the file XMIP_TEST_CLUSTER names,
            else the estate's test/xmip.toml.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:XMIP_TEST_CLUSTER)) {
        return $env:XMIP_TEST_CLUSTER
    }

    return Join-Path -Path (Get-XmipRepositoryRoot) -ChildPath 'test/xmip.toml'
}

function Read-XmipTestCluster {
    <#
        .SYNOPSIS
            A cluster's xmip.toml as a test run reads it: its name, its nodes
            in ordinal order, the roles each declares as written, and its
            scope. The module's one reading of a cluster's nodes.

        .DESCRIPTION
            Throws where the file is not there or names no cluster_name. A
            file that declares no node is a cluster of none, which a run asked
            for with -Nodes @().

        .PARAMETER Path
            The cluster's xmip.toml.
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

    $document = Read-XmipToml -Path $Path
    $service = Get-TomlValue -Node $document -Name 'service'
    [string] $name = [string] (Get-TomlValue -Node $service -Name 'cluster_name')

    if (-not $name) {
        throw "the cluster file $Path names no cluster_name"
    }

    $declared = Get-TomlValue -Node $document -Name 'nodes'
    [string[]] $names = @(Get-TomlKey -Node $declared)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $role = [ordered]@{}

    foreach ($node in $names) {
        $own = Get-TomlValue -Node $declared -Name $node
        $role[$node] = [string] (Get-TomlValue -Node $own -Name 'roles')
    }

    return [pscustomobject]@{
        Path  = $Path
        Name  = $name
        Nodes = $names
        Role  = $role
        Scope = "xmip:///$name"
    }
}

function Write-XmipTestCluster {
    <#
        .SYNOPSIS
            Writes a run's cluster xmip.toml from what was typed — the
            cluster, its nodes and the roles each declares — and returns its
            path.

        .DESCRIPTION
            <Path>/<Cluster>.xmip.toml: [service] with the cluster's name, and
            one [nodes.<node>] per node, with roles where -NodeRole states
            them, in node::NodeRole's words as ConvertTo-XmipNodeRole says
            them. A node -NodeRole does not name declares nothing. Replaced
            on every run, so the file is what was typed this time.

        .PARAMETER Cluster
            The cluster's name, as -Cluster gave it.

        .PARAMETER Nodes
            The nodes, as -Nodes gave them; none is a cluster of none.

        .PARAMETER NodeRole
            What -NodeRole stated per node.

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

        [Parameter(Mandatory)]
        [string] $Path
    )

    $declared = [ordered]@{}

    foreach ($node in @($Nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        [string] $roles = Get-XmipNodeRole -Name $node -NodeRole $NodeRole
        $declared[$node] = if ($roles -ne '') { [ordered]@{ roles = $roles } } else { [ordered]@{} }
    }

    $document = [ordered]@{
        service = [ordered]@{ name = 'xmip'; cluster_name = $Cluster }
    }

    if ($declared.Count -gt 0) {
        $document.nodes = $declared
    }

    [string] $file = Join-Path -Path $Path -ChildPath "$Cluster.xmip.toml"

    if ($PSCmdlet.ShouldProcess($file, 'Write the run''s cluster file')) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-XmipToml -Path $file -Value $document
    }

    return $file
}
