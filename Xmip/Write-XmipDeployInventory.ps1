#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Write-XmipDeployInventory {
    <#
        .SYNOPSIS
            Ansible's inventory for an environment, written from its
            environment file into the run folder as inventory.yml, and its
            path: generated YAML, never configuration (CONTRIBUTING).

        .DESCRIPTION
            The groups deploy/dsc/ansible/environment.yml plays to:

            - xmip_hypervisor_host: where the machines are made. On libvirt
              this machine, reached locally, with the system's Python,
              which has libvirt's binding; the machines with the values
              Microsoft DSC's machine documents are given, and the network.
            - linux and windows: how each machine is reached. AlmaLinux over
              SSH with the environment's own key and its known_hosts,
              checked strictly; Windows over WinRM as its Administrator,
              PowerShell 7 its interpreter.
            - xmip_nodes: each machine that runs a node, its node, its
              certificate's folder and its package, in the order the file
              lists them, with what every node is given.
            - xmip_name_server: the machine at the network's DNS server,
              where one of the machines is.

            Every group is written, empty where nothing is in it, so a play
            to one plays to none rather than a pattern Ansible warns of.

        .PARAMETER Read
            The environment as Get-XmipDeployEnvironment read it.

        .PARAMETER State
            The private state Initialize-XmipDeployState made.

        .PARAMETER Estate
            The estate's root.

        .PARAMETER Run
            The run folder.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter(Mandatory)]
        [hashtable] $State,

        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [string] $Run
    )

    [Collections.Specialized.OrderedDictionary] $linux = [ordered] @{}
    [Collections.Specialized.OrderedDictionary] $windows = [ordered] @{}
    [object[]] $machines = @(Get-XmipDeployMachine -Read $Read -State $State)
    foreach ($machine in $machines) {
        [hashtable] $reached = @{ ansible_host = $machine['address'] }
        if ($machine['image'].family -eq 'Windows') {
            $windows[$machine['name']] = $reached
        }
        else {
            $linux[$machine['name']] = $reached
        }
    }
    # A libvirt host is this controller, its Python the system's, which has
    # libvirt's binding; a Hyper-V host is the Windows host, over WinRM.
    [hashtable] $hypervisorHost = if ($Read.Hypervisor -eq 'hyperv') {
        @{
            $Read.Host = @{
                ansible_connection = 'winrm'
                ansible_port = 5985
                ansible_winrm_transport = 'ntlm'
                ansible_pwsh_interpreter = 'pwsh'
            }
        }
    }
    else {
        @{
            localhost = @{
                ansible_connection = 'local'
                ansible_python_interpreter = '/usr/bin/python3'
            }
        }
    }
    [Collections.Specialized.OrderedDictionary] $children = [ordered] @{
        xmip_hypervisor_host = @{
            hosts = $hypervisorHost
            vars = [ordered] @{
                xmip_hypervisor = $Read.Hypervisor
                xmip_root = $Read.Common.root
                xmip_network = $Read.Common.network
                xmip_network_machines = @($Read.Machines | ForEach-Object {
                        @{ name = $_['name']; address = $_['address'] } })
                xmip_names = $Read.Names
                xmip_machines = $machines
                xmip_machine_definition = Join-Path $Estate 'deploy/dsc/machine/machine.ps1'
                xmip_state = $State.Folder
            }
        }
        linux = @{
            hosts = $linux
            vars = [ordered] @{
                ansible_connection = 'ssh'
                ansible_user = $Read.Common.linuxAccount
                ansible_ssh_private_key_file = $State.Key
                ansible_ssh_common_args = "-o UserKnownHostsFile=$($State.KnownHosts) " +
                    '-o StrictHostKeyChecking=yes'
                # AlmaLinux's own Python, named, never discovered: one
                # installed later is never taken instead.
                ansible_python_interpreter = '/usr/bin/python3'
            }
        }
        windows = @{
            hosts = $windows
            vars = [ordered] @{
                ansible_connection = 'winrm'
                ansible_port = 5985
                ansible_winrm_transport = 'ntlm'
                ansible_user = 'Administrator'
                ansible_pwsh_interpreter = 'pwsh'
            }
        }
    }
    [Collections.Specialized.OrderedDictionary] $nodes = [ordered] @{}
    foreach ($node in $Read.Nodes) {
        $nodes[$node.machine.name] = @{
            xmip_node_name = $node.node
            xmip_identity = Join-Path $Read.Node.identity $node.node
            xmip_package = $Read.Node.packages[$node.machine.family].path
        }
    }
    $children['xmip_nodes'] = @{ hosts = $nodes }
    if ($nodes.Count -gt 0) {
        $children['xmip_nodes'].vars = [ordered] @{
            xmip_cluster_configuration = $Read.Node.configuration
            xmip_slicer = $Read.Node.slicer
            xmip_authority = $Read.Node.authority
            xmip_far_end = $Read.Node.farEnd
        }
    }
    $children['xmip_name_server'] = @{
        hosts = if ($null -ne $Read.NameServer) { @{ $Read.NameServer.name = @{} } } else { @{} }
    }
    [hashtable] $inventory = @{
        all = [ordered] @{
            vars = [ordered] @{
                xmip_environment = $Read.Name
                xmip_cluster_name = $Read.Cluster
                xmip_domain = $Read.Common.domainName
            }
            children = $children
        }
    }
    [string] $path = Join-Path $Run 'inventory.yml'
    Write-XmipYaml -Path $path -Value $inventory
    return $path
}
