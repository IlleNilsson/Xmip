#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipDeployStep {
    <#
        .SYNOPSIS
            Microsoft DSC's documents to apply, in order, each with the
            values of the parameters it declares: the network, each machine,
            the domain's controller where the file names one, the names
            where one of the machines is the environment's DNS server, each
            other Windows machine joined to the domain, then each node on
            its machine, in the order the environment file lists the
            machines, and last every node started together.

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
    # The domain's controller before the names, which go into the zone its
    # DNS server holds, and each member after; each restarts, so it is set
    # again until it answers as asked.
    [string] $domain = Join-Path $environment 'domain.dsc.yaml'
    if ($null -ne $Read.Domain) {
        @{
            Name = "domain-$($Read.Domain.controller.name)"
            Document = $domain
            Value = @{ common = $reach; machine = $Read.Domain.controller
                domain = $Read.Domain.name; controller = $true }
            Install = $true
        }
    }
    if ($null -ne $Read.NameServer -and $Read.Names.Count -gt 0) {
        @{
            Name = 'names'
            Document = Join-Path $environment 'names.dsc.yaml'
            Value = @{ common = $reach; server = $Read.NameServer
                zone = $Read.Common.domainName; records = $Read.Names; tools = $Read.Tools }
        }
    }
    foreach ($member in @($Read.Domain | Where-Object { $_ } | ForEach-Object { $_.members })) {
        @{
            Name = "domain-$($member.name)"
            Document = $domain
            Value = @{ common = $reach; machine = $member; domain = $Read.Domain.name
                controller = $false }
            Install = $true
        }
    }
    if ($Read.Nodes.Count -eq 0) {
        return
    }
    [hashtable] $given = $Read.Node.Clone()
    $given.Remove('packages')
    $given['cluster'] = $Read.Cluster
    # Every node by its name at its machine's address, which each machine
    # keeps in its hosts file (NodePackage.ps1).
    $given['names'] = (@($Read.Nodes | ForEach-Object {
                "$($_.machine.address) $($_.node)" }) -join "`n")
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
                tools = $Read.Tools
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
