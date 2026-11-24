#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipDeployEnvironment {
    <#
        .SYNOPSIS
            An environment file read once for both technologies: what its
            machines and its nodes are, every path resolved, every value a
            template needs checked, so a missing one is refused in words
            before anything is made.

        .DESCRIPTION
            The environment file is the one place that says what an
            environment is (deploy/dsc/README.md): the technology whose
            template set makes it, msdsc or ansible, never a mix (ADR-0015,
            amendment 2026-10-09); the hypervisor; the network, images and
            machines, with the node each machine runs; and what a node is
            given. Microsoft DSC's documents are given their parameters from
            this, and Ansible's inventory is written from it: the YAML each
            tool reads is generated, never configuration. A path not rooted
            is the estate's; ~ is the home folder.

        .PARAMETER Environment
            The environment file, as Read-XmipToml reads it.

        .PARAMETER Estate
            The estate's root.

        .PARAMETER Run
            The run folder, .local-work/deploy/<environment>.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment,

        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [string] $Run
    )

    [string] $technology = Get-TomlValue -Node $Environment -Name 'technology' -Default ''
    if ($technology -notin 'msdsc', 'ansible') {
        throw ('REFUSED: the environment file names the template set that makes it in a line ' +
            'of its own, technology = "msdsc" or technology = "ansible"; ' +
            "it says '$technology'.")
    }
    [string] $hypervisor = Get-TomlValue -Node $Environment -Name 'hypervisor'
    [string] $template = if ($technology -eq 'msdsc') {
        Join-Path $Estate "deploy/dsc/msdsc/$hypervisor/machine.dsc.yaml"
    }
    else { Join-Path $Estate "deploy/dsc/ansible/roles/xmip_machine/tasks/$hypervisor.yml" }
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
        throw "REFUSED: $technology has no template for the hypervisor '$hypervisor': $template"
    }
    $network = Get-TomlValue -Node $Environment -Name 'network'
    $images = Get-TomlValue -Node $Environment -Name 'images'
    [string] $prefix = Get-TomlValue -Node $network -Name 'prefix'
    [string] $name = Get-TomlValue -Node $Environment -Name 'name'
    [hashtable] $common = @{
        environment = $name
        root = Get-TomlValue -Node $Environment -Name 'root'
        secretPath = Resolve-XmipDeployPath -Estate $Estate -Path (
            Get-TomlValue -Node $Environment -Name 'secret' -Default '')
        linuxAccount = Get-TomlValue -Node $Environment -Name 'linux_account' -Default ''
        domainName = Get-TomlValue -Node $Environment -Name 'domain'
        network = @{
            name = Get-TomlValue -Node $network -Name 'name'
            bridge = Get-TomlValue -Node $network -Name 'bridge' -Default ''
            prefix = $prefix
            gateway = Get-TomlValue -Node $network -Name 'gateway'
            prefixLength = [int] ($prefix -replace '^.*/', '')
            dnsServer = Get-TomlValue -Node $network -Name 'dns_server'
            enableNat = [bool] (Get-TomlValue -Node $network -Name 'nat' -Default $false)
        }
    }
    [Collections.Generic.List[hashtable]] $machines = @()
    [Collections.Generic.List[hashtable]] $nodes = @()
    # Whether a machine reaches past the network: the network's default,
    # each machine's own where it says; one that does not is given no
    # gateway, and reaches the network alone.
    [bool] $internet = [bool] (Get-TomlValue -Node $network -Name 'internet' -Default $true)
    foreach ($machine in @(Get-TomlValue -Node $Environment -Name 'machines' -Default @())) {
        [hashtable] $value = $common.Clone()
        $value['name'] = Get-TomlValue -Node $machine -Name 'name'
        $value['address'] = Get-TomlValue -Node $machine -Name 'address'
        $value['network'] = $common.network.Clone()
        if (-not [bool] (Get-TomlValue -Node $machine -Name 'internet' -Default $internet)) {
            $value['network']['gateway'] = ''
        }
        $value['image'] = ConvertTo-XmipTomlTable -Node (Get-TomlValue -Node $images -Name (
                Get-TomlValue -Node $machine -Name 'image'))
        $value['image']['path'] = Resolve-XmipDeployPath -Estate $Estate -Path (
            [string] $value['image']['path'])
        $value['memoryGB'] = [int] (Get-TomlValue -Node $machine -Name 'memory_gb')
        $value['dynamicMemory'] = Get-XmipDeployDynamicMemory -Machine $machine -Hypervisor (
            $hypervisor) -Family $value['image'].family
        $value['cpu'] = [int] (Get-TomlValue -Node $machine -Name 'cpu')
        $value['diskGB'] = [int] (Get-TomlValue -Node $machine -Name 'disk_gb')
        $value['pool'] = $name
        $machines.Add($value)
        [string[]] $runs = @(Get-TomlValue -Node $machine -Name 'nodes' -Default @())
        if ($runs.Count -gt 1) {
            throw ("REFUSED: $($value['name']) names $($runs -join ', '): a machine runs one " +
                'node, which its package lays out in one folder.')
        }
        foreach ($node in $runs) {
            $nodes.Add(@{
                    node = $node
                    machine = @{
                        name = $value['name']
                        address = $value['address']
                        family = $value['image'].family
                    }
                })
        }
    }
    [string] $dnsServer = $common.network.dnsServer
    [hashtable] $read = @{
        Name = $name
        Technology = $technology
        Hypervisor = $hypervisor
        Template = Split-Path -Path $template -Parent
        Common = $common
        Machines = $machines.ToArray()
        Names = @(Get-XmipDeployName -Environment $Environment)
        NameServer = @($machines | Where-Object { $_['address'] -eq $dnsServer } |
                ForEach-Object { @{ name = $_['name']; address = $_['address']
                        family = $_['image'].family } }) | Select-Object -First 1
        Nodes = $nodes.ToArray()
        Placed = (@($nodes | ForEach-Object { $_.node }) -join ',')
        Cluster = Get-TomlValue -Node $Environment -Name 'cluster' -Default ''
        Host = Get-TomlValue -Node $Environment -Name 'host' -Default ''
    }
    # Ansible reaches a Hyper-V host from its controller, over WinRM.
    if ($technology -eq 'ansible' -and $hypervisor -eq 'hyperv' -and -not $read.Host) {
        throw ('REFUSED: ansible makes Hyper-V machines from its controller: host names ' +
            'the Windows host''s address as the controller reaches it.')
    }
    Add-XmipDeployDomain -Environment $Environment -Read $read
    Add-XmipDeployGateway -Environment $Environment -Read $read
    if ($nodes.Count -gt 0) {
        $read['Node'] = Get-XmipDeployNodeValue -Environment $Environment -Estate $Estate -Run (
            $Run) -Read $read
    }
    Add-XmipDeployFarEnd -Environment $Environment -Estate $Estate -Read $read
    # The tools DSC is brought with, for each family a document is applied
    # on: the nodes' and far ends' machines, the DNS server and the domain's.
    [string[]] $families = @(@(@($nodes) + @($read.FarEnds) |
                ForEach-Object { $_.machine.family }) + @(
            $read.NameServer | Where-Object { $_ } | ForEach-Object { $_.family }) + @(
            $read.Domain | Where-Object { $_ } | ForEach-Object { 'Windows' }) |
            Sort-Object -Unique)
    $read['Tools'] = if ($technology -eq 'msdsc') {
        Get-XmipDeployTool -Environment $Environment -Estate $Estate -Family $families
    }
    else { @{ Linux = @{}; Windows = @{} } }
    return $read
}

function Get-XmipDeployTool {
    <#
        .SYNOPSIS
            msdsc's tools for each family -Family names, pwsh and dsc, each
            a path that is there and its SHA-256: a fresh machine of either
            family has neither PowerShell 7 nor DSC, Windows Server shipping
            Windows PowerShell alone.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment,

        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Family
    )

    [hashtable] $tools = @{ Linux = @{}; Windows = @{} }
    $carried = Get-TomlValue -Node $Environment -Name 'tools' -Default $null
    foreach ($each in $Family) {
        $tool = Get-TomlValue -Node $carried -Name $each -Default $null
        foreach ($name in 'pwsh', 'dsc') {
            $entry = Get-TomlValue -Node $tool -Name $name -Default $null
            [string] $file = Resolve-XmipDeployPath -Estate $Estate -Path (
                Get-TomlValue -Node $entry -Name 'path' -Default '')
            [string] $sha256 = Get-TomlValue -Node $entry -Name 'sha256' -Default ''
            [bool] $there = $file -and (Test-Path -LiteralPath $file -PathType Leaf)
            if (-not $there -or -not $sha256) {
                throw ("REFUSED: msdsc brings DSC to each $each machine it applies a document " +
                    "on: [tools.$each] $name needs path and sha256: '$file'.")
            }
            $tools[$each][$name] = @{ path = $file; sha256 = $sha256.ToLowerInvariant() }
        }
    }
    return $tools
}

function Get-XmipDeployNodeValue {
    <#
        .SYNOPSIS
            What every node of the environment is given, each value checked:
            the cluster's file, this machine's xmip-service that slices and
            signs it, the authority that signs and the folder of each node's
            certificate, the Parties' far end and the package for each family
            a node runs on.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment,

        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [string] $Run,

        [Parameter(Mandatory)]
        [hashtable] $Read
    )

    [hashtable] $given = @{}
    foreach ($key in 'configuration', 'slicer', 'authority', 'identity') {
        [string] $path = Resolve-XmipDeployPath -Estate $Estate -Path (
            Get-TomlValue -Node $Environment -Name $key -Default '')
        if (-not $path -or -not (Test-Path -LiteralPath $path)) {
            throw "REFUSED: the environment's nodes need $key, a path that is there: '$path'."
        }
        $given[$key] = $path
    }
    if (-not $Read.Cluster) {
        throw 'REFUSED: the environment''s nodes need cluster, the cluster''s name.'
    }
    # The Parties' far ends, one or a list, and whether each Receive
    # Location listens on its node for their push (ADR-0028, amendment
    # 2026-11-22).
    $given['farEnd'] = @(Get-TomlValue -Node $Environment -Name 'far_end' -Default @()) -join ','
    $given['listen'] = [bool] (Get-TomlValue -Node $Environment -Name 'listen' -Default $false)
    # Who operates the nodes, each listed among every slice's [operate]
    # operators (xmip-service --slice --operators): a certificate's subject,
    # CN=<person>, or an account. None given, no one operates them.
    $given['operators'] = (@(Get-TomlValue -Node $Environment -Name 'operators' -Default @()) |
            ForEach-Object { ([string] $_).Trim() } | Where-Object { $_ }) -join ','
    $given['slices'] = Join-Path $Run 'slice'
    [hashtable] $packages = @{ Linux = @{}; Windows = @{} }
    $packaged = Get-TomlValue -Node $Environment -Name 'packages' -Default $null
    foreach ($family in @($Read.Nodes | ForEach-Object { $_.machine.family } |
            Sort-Object -Unique)) {
        $package = Get-TomlValue -Node $packaged -Name $family -Default $null
        [string] $path = Resolve-XmipDeployPath -Estate $Estate -Path (
            Get-TomlValue -Node $package -Name 'path' -Default '')
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "REFUSED: a $family node needs [packages.$family] path, the package: '$path'."
        }
        $packages[$family] = @{ path = $path; file = 'xmip' + [IO.Path]::GetExtension($path) }
        # The module libraries the cluster's file names, built for this
        # system: each is carried beside every node's configuration, where
        # its `library_path` is read (ADR-0066, amendment 2026-11-21).
        [string] $modules = Get-TomlValue -Node $package -Name 'modules' -Default ''
        if ($modules) {
            $modules = Resolve-XmipDeployPath -Estate $Estate -Path $modules
            if (-not (Test-Path -LiteralPath $modules -PathType Container)) {
                throw "REFUSED: [packages.$family] modules names no folder: '$modules'."
            }
            $packages[$family].modules = $modules
        }
        # The same libraries as one file, which msdsc sends beside the
        # package: a zip, empty where the cluster names none, written once
        # the run holds its lock (Invoke-XmipDeployStep).
        $packages[$family].archive = Join-Path -Path $Run -ChildPath (
            "modules-$($family.ToLowerInvariant()).zip")
    }
    $given['packages'] = $packages
    return $given
}

function New-XmipDeployModuleArchive {
    <#
        .SYNOPSIS
            The module libraries of each family's [packages.<family>]
            modules folder as the one zip its archive names, which msdsc
            sends beside the package and the node unpacks into its
            configuration folder; an empty zip where it names none. Written
            over what is there.

        .PARAMETER Packages
            The environment's packages, by family, as
            Get-XmipDeployEnvironment reads them.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Packages
    )

    foreach ($package in @($Packages.Values | Where-Object { $_['archive'] })) {
        [object[]] $libraries = @()
        if ($package['modules']) {
            $libraries = @(Get-ChildItem -LiteralPath $package['modules'] -File)
        }
        $null = New-Item -ItemType Directory -Path (Split-Path $package['archive']) -Force
        $file = [System.IO.File]::Open($package['archive'], [System.IO.FileMode]::Create)
        $zip = [System.IO.Compression.ZipArchive]::new(
            $file, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($library in $libraries) {
                $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $zip, $library.FullName, $library.Name)
            }
        }
        finally {
            $zip.Dispose()
            $file.Dispose()
        }
    }
}

function Resolve-XmipDeployPath {
    <#
        .SYNOPSIS
            A path of the environment file as this machine reads it: ~ is the
            home folder, and a path not rooted is the estate's. Empty stays
            empty.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Path
    )

    if (-not $Path) {
        return ''
    }
    if ($Path -eq '~' -or $Path -match '^~[\\/]') {
        return Join-Path $HOME $Path.Substring([Math]::Min(2, $Path.Length))
    }
    if ([IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $Estate $Path
}

function Get-XmipDeployName {
    <#
        The names the environment adds to its machines' own: each node and
        each far end a machine runs, at that machine's address, and the
        cluster at every address that runs one of its nodes.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment
    )

    [string[]] $running = @()
    foreach ($machine in @(Get-TomlValue -Node $Environment -Name 'machines' -Default @())) {
        [string[]] $nodes = @(Get-TomlValue -Node $machine -Name 'nodes' -Default @())
        [string] $address = Get-TomlValue -Node $machine -Name 'address'
        # A far end is found by its own name, as a node is (ADR-0028,
        # amendment 2026-11-22).
        foreach ($external in @(Get-TomlValue -Node $machine -Name 'external' -Default @())) {
            @{ name = $external; addresses = @($address) }
        }
        if ($nodes.Count -eq 0) {
            continue
        }
        foreach ($node in $nodes) {
            @{ name = $node; addresses = @($address) }
        }
        $running += $address
    }
    [string] $cluster = Get-TomlValue -Node $Environment -Name 'cluster' -Default ''
    if ($cluster -ne '' -and $running.Count -gt 0) {
        @{ name = $cluster; addresses = $running }
    }
}
