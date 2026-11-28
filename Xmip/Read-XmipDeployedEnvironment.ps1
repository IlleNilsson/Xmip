#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipDeployRunFolder {
    <#
        .SYNOPSIS
            The run folder of a cluster's environment, .local-work/deploy/<cluster>:
            the log, the YAML each technology is given and, on Windows, the
            private state (Get-XmipDeployStateFolder).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster
    )

    return Join-Path (Get-XmipEstateLayout).Deploy $Cluster
}

function Read-XmipDeployedEnvironment {
    <#
        .SYNOPSIS
            What a run of Deploy-XmipEnvironment that applied recorded of a
            cluster's environment on this host, deployed.toml in its private
            state: the cluster file's path and SHA-256, the technology, the
            hypervisor, the folder of the operator certificate the cluster's
            authority signed, and each node's and far end's virtual machine
            and address; $null where no environment of the cluster is
            deployed here.

        .DESCRIPTION
            What Start-XmipTest -VirtualMachine runs by: it never makes or
            starts a virtual machine, and resolves no name (ADR-0015 and
            ADR-0028, amendments 2026-11-25).

        .PARAMETER Cluster
            The cluster, by the name its file declares (Get-XmipClusterName).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster
    )

    [string] $folder = Get-XmipDeployStateFolder -Name $Cluster -Run (
        Get-XmipDeployRunFolder -Cluster $Cluster)
    [string] $path = Join-Path $folder 'deployed.toml'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    $read = Read-XmipToml -Path $path
    [hashtable] $deployed = @{ Folder = $folder; Path = $path }
    [hashtable] $named = @{ Cluster = 'cluster'; File = 'file'; Sha256 = 'sha256'
        Technology = 'technology'; Hypervisor = 'hypervisor'; Operator = 'operator' }
    foreach ($key in $named.Keys) {
        $deployed[$key] = [string] (Get-TomlValue -Node $read -Name $named[$key] -Default '')
    }
    foreach ($table in @(@('nodes', 'Nodes'), @('far_ends', 'FarEnds'))) {
        [Collections.Specialized.OrderedDictionary] $each = [ordered] @{}
        $given = Get-TomlValue -Node $read -Name $table[0] -Default $null
        foreach ($name in @(Get-TomlKey -Node $given)) {
            $each[$name] = [string] (Get-TomlValue -Node $given -Name $name)
        }
        $deployed[$table[1]] = $each
    }
    return $deployed
}

function Write-XmipDeployedEnvironment {
    <#
        .SYNOPSIS
            Records in the private state what a run that applied made, as
            deployed.toml, which Read-XmipDeployedEnvironment reads: written
            whole once every step is in its desired state.

        .PARAMETER Read
            The environment as Get-XmipDeployEnvironment read it.

        .PARAMETER State
            The private state Initialize-XmipDeployState made.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter(Mandatory)]
        [hashtable] $State
    )

    [Collections.Specialized.OrderedDictionary] $nodes = [ordered] @{}
    foreach ($node in $Read.Nodes) {
        $nodes[$node.node] = $node.machine.address
    }
    [Collections.Specialized.OrderedDictionary] $farEnds = [ordered] @{}
    foreach ($far in @($Read.FarEnds)) {
        $farEnds[$far.name] = $far.machine.address
    }
    [Collections.Specialized.OrderedDictionary] $deployed = [ordered] @{
        cluster    = $Read.Cluster
        file       = $Read.File
        sha256     = $Read.Sha256
        technology = $Read.Technology
        hypervisor = $Read.Hypervisor
        operator   = [string] $State['Operator']
        nodes      = $nodes
        far_ends   = $farEnds
    }
    Write-XmipToml -Path (Join-Path $State.Folder 'deployed.toml') -Value $deployed
}
