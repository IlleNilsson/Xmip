#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipDeployStep {
    <#
        .SYNOPSIS
            Microsoft DSC's documents to apply, in order, each with the
            values of the parameters it declares: the network, each machine,
            the names where one of the machines is the environment's DNS
            server, then each node on its machine, in the order the
            environment file lists the machines, and last every node
            started together.

        .DESCRIPTION
            A machine's step is marked Install: the command applies it until
            the machine is installed before it goes on, so one machine
            installs at a time. A node's step is the environment template's
            machine.dsc.yaml, applied here: it slices and signs the node's
            configuration, brings DSC to the machine and applies
            node.dsc.yaml there.

        .PARAMETER Read
            The environment as Get-XmipDeployEnvironment read it.

        .PARAMETER State
            The private state Initialize-XmipDeployState made.

        .PARAMETER Estate
            The estate's root.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter(Mandatory)]
        [hashtable] $State,

        [Parameter(Mandatory)]
        [string] $Estate
    )

    [hashtable] $common = $Read.Common.Clone()
    $common['machines'] = @($Read.Machines | ForEach-Object {
            @{ name = $_['name']; address = $_['address'] }
        })
    $common['names'] = $Read.Names
    @{ Name = 'network'; Document = Join-Path $Read.Template 'network.dsc.yaml'; Value = $common }
    foreach ($value in @(Get-XmipDeployMachine -Read $Read -State $State)) {
        [string] $document = Join-Path $Read.Template 'machine.dsc.yaml'
        @{ Name = $value['name']; Document = $document; Value = $value; Install = $true }
    }
    [string] $environment = Join-Path $Estate 'deploy/dsc/msdsc/environment'
    [hashtable] $reach = @{
        linuxAccount = $Read.Common.linuxAccount
        secretPath = $Read.Common.secretPath
        keyPath = $State.Key
        knownHosts = $State.KnownHosts
    }
    if ($null -ne $Read.NameServer -and $Read.Names.Count -gt 0) {
        @{
            Name = 'names'
            Document = Join-Path $environment 'names.dsc.yaml'
            Value = @{ common = $reach; server = $Read.NameServer
                zone = $Read.Common.domainName; records = $Read.Names }
        }
    }
    if ($Read.Nodes.Count -eq 0) {
        return
    }
    [hashtable] $given = $Read.Node.Clone()
    $given.Remove('packages')
    $given.Remove('tools')
    $given['cluster'] = $Read.Cluster
    $given['program'] = $given['slicer']
    $given.Remove('slicer')
    foreach ($key in $reach.Keys) {
        $given[$key] = $reach[$key]
    }
    foreach ($node in $Read.Nodes) {
        @{
            Name = $node.node
            Document = Join-Path $environment 'machine.dsc.yaml'
            Value = @{
                common = $given
                packages = $Read.Node.packages
                tools = $Read.Node.tools
                placed = $Read.Placed
                node = $node.node
                machine = $node.machine
            }
        }
    }
    @{
        Name = 'started'
        Document = Join-Path $environment 'started.dsc.yaml'
        Value = @{ common = $reach; nodes = $Read.Nodes }
    }
}

function Get-XmipDeployMachine {
    <#
        .SYNOPSIS
            Each machine as a machine template is given it, in either
            technology: what the environment file says of it, with the
            technology making it, which its host's record of it names, the
            environment's public SSH key its account is given and, for an
            AlmaLinux machine, the host key its kickstart gives it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter(Mandatory)]
        [hashtable] $State
    )

    foreach ($machine in $Read.Machines) {
        [hashtable] $value = $machine.Clone()
        $value['technology'] = $Read.Technology
        $value['sshPublicKeyPath'] = "$($State.Key).pub"
        $value['hostKeyPath'] = if ($State.HostKey.ContainsKey($machine['name'])) {
            $State.HostKey[$machine['name']]
        }
        else { '' }
        $value
    }
}
