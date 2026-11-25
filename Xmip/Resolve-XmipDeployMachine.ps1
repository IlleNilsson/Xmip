#requires -Version 7.7.0

Set-StrictMode -Version Latest

# What a machine is given where neither [environment.machine] nor its own
# table says: the built-in defaults of every hardware assumption (the owner,
# 2026-10-03: configurable per cluster and node, kept in the Cluster TOML).
[hashtable] $script:XmipDeployMachineDefault = @{ cpu = 2; memory_gb = 2; disk_gb = 64 }

# A Windows computer's name is at most 15 characters, its NetBIOS name's.
[int] $script:XmipDeployNameLength = 15

function Resolve-XmipDeployMachine {
    <#
        .SYNOPSIS
            Every virtual machine a cluster file's [environment] makes, in the
            order its addresses are given: the machines of their own that run
            no node and no far end, in the file's order, then the far ends,
            senders then receivers, then the nodes in the file's order. Pure:
            it reads the file alone.

        .DESCRIPTION
            One virtual machine for each node and far end, and each other name
            of [environment.machines] (ADR-0015, amendment 2026-11-25). Each is
            named XMIP-<name>; is sized by its own table of
            [environment.machines], else [environment.machine], else the
            built-in defaults, key by key, dynamic_memory whole; runs the
            image its os names; reaches past the network where its node
            declares the Node capability online (ADR-0056, amendment
            2026-11-24); and says in one line its role, from what the file
            declares, and its operating system, in its image's own words:
            its description, which Hyper-V keeps as the VM's notes and
            libvirt as the domain's description (the owner, 2026-11-25:
            "When you set up virtual machines, there is a description field.
            I want it to state Role and OS type").

            Refused in words: a machine with no os, an os no
            [environment.images] names, a far end named as a node or twice,
            and a Windows machine whose name is longer than its NetBIOS name
            may be.

        .PARAMETER Cluster
            The cluster file, as Read-XmipToml reads it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Cluster
    )

    $environment = Get-TomlValue -Node $Cluster -Name 'environment' -Default $null
    $nodes = Get-TomlValue -Node $Cluster -Name 'nodes' -Default $null
    $farEnds = Get-TomlValue -Node $environment -Name 'far_ends' -Default $null
    $own = Get-TomlValue -Node $environment -Name 'machines' -Default $null
    [string[]] $nodeNames = @(Get-TomlKey -Node $nodes)
    [Collections.Specialized.OrderedDictionary] $farKind = [ordered] @{}
    foreach ($side in @(@('senders', 'Sender'), @('receivers', 'Receiver'))) {
        foreach ($name in @(Get-TomlValue -Node $farEnds -Name $side[0] -Default @())) {
            if ($farKind.Contains($name) -or $name -in $nodeNames) {
                throw ("REFUSED: [environment.far_ends] names $name twice, or as a node: " +
                    'a far end and a node are each a machine of their own.')
            }
            $farKind[$name] = $side[1]
        }
    }
    [Collections.Generic.List[hashtable]] $listed = @()
    foreach ($name in @(Get-TomlKey -Node $own | Where-Object {
                $_ -notin $nodeNames -and -not $farKind.Contains($_) })) {
        $listed.Add(@{ name = $name; kind = 'machine' })
    }
    foreach ($name in $farKind.Keys) {
        $listed.Add(@{ name = $name; kind = 'far end'; role = "$($farKind[$name]) far end" })
    }
    foreach ($name in $nodeNames) {
        $declared = Get-TomlValue -Node $nodes -Name $name
        [string] $said = Get-TomlValue -Node $declared -Name 'roles' -Default ''
        [string[]] $roles = @($said -split '[,+]' | ForEach-Object { $_.Trim() } |
                Where-Object { $_ })
        [string[]] $capabilities = @(
            Get-TomlValue -Node $declared -Name 'capabilities' -Default @())
        [string] $role = if ($roles.Count -eq 0) { 'Node' }
        else { (Join-XmipDeployWord -Word $roles) + ' node' }
        $listed.Add(@{
                name = $name; kind = 'node'; roles = $roles; role = $role
                online = 'online' -in $capabilities; storage = 'storage' -in $roles
            })
    }
    [string] $controller = Get-TomlValue -Node $environment -Name 'domain_controller' -Default ''
    [string] $gateway = Get-TomlValue -Node $environment -Name 'gateway' -Default ''
    $images = Get-TomlValue -Node $environment -Name 'images' -Default $null
    $default = Get-TomlValue -Node $environment -Name 'machine' -Default $null
    foreach ($machine in $listed) {
        $mine = Get-TomlValue -Node $own -Name $machine.name -Default $null
        foreach ($key in 'os', 'cpu', 'memory_gb', 'disk_gb', 'dynamic_memory') {
            $built = $script:XmipDeployMachineDefault[$key]
            $machine[$key] = Get-TomlValue -Node $mine -Name $key -Default (
                Get-TomlValue -Node $default -Name $key -Default $built)
        }
        $machine['purpose'] = [string] (Get-TomlValue -Node $mine -Name 'purpose' -Default '')
        [string] $table = "[environment.machines.$($machine.name)]"
        if (-not $machine.os) {
            throw ("REFUSED: $($machine.name)'s virtual machine names no os: give it one in " +
                "$table, or every machine's in [environment.machine].")
        }
        $image = Get-TomlValue -Node $images -Name $machine.os -Default $null
        if ($null -eq $image) {
            throw ("REFUSED: $($machine.name) runs $($machine.os), which no " +
                '[environment.images] names.')
        }
        $machine['family'] = [string] (Get-TomlValue -Node $image -Name 'family' -Default '')
        $machine['machine'] = "XMIP-$($machine.name)"
        [int] $most = $script:XmipDeployNameLength
        if ($machine.family -eq 'Windows' -and $machine.machine.Length -gt $most) {
            throw ("REFUSED: $($machine.machine) is longer than the $most characters a " +
                'Windows computer''s name may be.')
        }
        if ($machine.kind -ne 'node') {
            $machine['online'] = $false
            $machine['storage'] = $false
        }
        if ($machine.kind -eq 'machine') {
            [hashtable] $named = @{ Controller = $controller; Gateway = $gateway }
            $machine['role'] = Get-XmipDeployPurpose -Machine $machine @named
        }
        [string] $system = Get-TomlValue -Node $image -Name 'name' -Default (
            Get-TomlValue -Node $image -Name 'edition' -Default $machine.family)
        $machine['description'] = "$($machine.role) $($machine.name) $([char] 0x00B7) $system"
        $machine
    }
}

function Get-XmipDeployPurpose {
    <#
        .SYNOPSIS
            What a machine that runs no node and no far end is for, in words:
            its own purpose where its table says one; else the domain
            controller and the gateway it is named as; else a machine.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Machine,

        [Parameter()]
        [string] $Controller = '',

        [Parameter()]
        [string] $Gateway = ''
    )

    if ($Machine.purpose) {
        [string] $said = [string] $Machine.purpose
        return $said.Substring(0, 1).ToUpperInvariant() + $said.Substring(1)
    }
    [string[]] $is = @(
        if ($Machine.name -eq $Controller) { 'domain controller' }
        if ($Machine.name -eq $Gateway) { 'gateway' }
    )
    if ($is.Count -eq 0) {
        return 'Machine'
    }
    return Join-XmipDeployWord -Word $is
}

function Join-XmipDeployWord {
    <#
        .SYNOPSIS
            Words as a sentence says them, the first capitalized: one, two
            joined by "and", more with commas and "and" before the last.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Word
    )

    [string] $said = if ($Word.Count -eq 1) { $Word[0] }
    else { ($Word[0..($Word.Count - 2)] -join ', ') + ' and ' + $Word[-1] }
    return $said.Substring(0, 1).ToUpperInvariant() + $said.Substring(1)
}
