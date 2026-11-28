#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipDeployEnvironment {
    <#
        .SYNOPSIS
            A cluster file's environment read once for both technologies:
            what its virtual machines and its nodes are, with what this host
            gives them, every value a template needs checked, so a missing
            one is refused in words before anything is made.

        .DESCRIPTION
            One file says what an environment is: the cluster file, its nodes
            and, in [environment], its far ends, machines, network and images
            (ADR-0015, amendment 2026-11-25; the owner, 2026-11-25: *I still
            don't get why there is a need for two files?*). Resolve-XmipDeployMachine
            lists its machines, one for each node and far end and each machine
            of its own, in the order their addresses are given: the host takes
            the network's first address, the machines the next. The host
            facts, Get-XmipDeployHost's, give the rest. Microsoft DSC's
            documents are given their parameters from this, and Ansible's
            inventory is written from it: the YAML each tool reads is
            generated, never configuration.

            Refused: a technology with no template for the hypervisor; a
            Windows machine on a Linux host, which is not made yet (ADR-0015,
            the third amendment of 2026-11-22); a network too small for its
            machines; a domain controller or gateway that is no Windows
            machine of the environment.

        .PARAMETER Cluster
            The cluster file, as Read-XmipToml reads it.

        .PARAMETER Name
            The cluster's name, as the file declares it (Get-XmipClusterName).

        .PARAMETER File
            The cluster file's path, each node's configuration sliced from it.

        .PARAMETER Technology
            msdsc or ansible: the template set that makes it all.

        .PARAMETER Hypervisor
            hyperv or libvirt, Get-XmipDeployHypervisor's.

        .PARAMETER Facts
            What this host gives the environment, Get-XmipDeployHost's.

        .PARAMETER Estate
            The estate's root.

        .PARAMETER Run
            The run folder, .local-work/deploy/<cluster>.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Cluster,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $File,

        [Parameter(Mandatory)]
        [ValidateSet('msdsc', 'ansible')]
        [string] $Technology,

        [Parameter(Mandatory)]
        [string] $Hypervisor,

        [Parameter(Mandatory)]
        [hashtable] $Facts,

        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [string] $Run
    )

    [string] $template = if ($Technology -eq 'msdsc') {
        Join-Path $Estate "deploy/dsc/msdsc/$Hypervisor/machine.dsc.yaml"
    }
    else { Join-Path $Estate "deploy/dsc/ansible/roles/xmip_machine/tasks/$Hypervisor.yml" }
    if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
        throw "REFUSED: $Technology has no template for the hypervisor '$Hypervisor': $template"
    }
    $environment = Get-TomlValue -Node $Cluster -Name 'environment' -Default $null
    $images = Get-TomlValue -Node $environment -Name 'images' -Default $null
    [hashtable[]] $listed = @(Resolve-XmipDeployMachine -Cluster $Cluster)
    [string[]] $windows = @($listed | Where-Object { $_.family -eq 'Windows' } |
            ForEach-Object { $_.machine })
    if ($Hypervisor -eq 'libvirt' -and $windows.Count -gt 0) {
        throw ("REFUSED: a Linux host makes no Windows machine yet, $($windows -join ', '): " +
            'their Administrator secret is read on Windows alone and PowerShell on Linux has ' +
            'no WinRM client (ADR-0015, the third amendment of 2026-11-22). A smaller plan is a ' +
            'smaller cluster file, its every machine AlmaLinux.')
    }
    $range = ConvertTo-XmipDeployRange -Prefix $Facts.Network
    if ($range.First + $listed.Count + 2 -gt $range.Last) {
        throw ("REFUSED: $($Facts.Network) holds too few addresses for the host and " +
            "$($listed.Count) machines.")
    }
    [string] $hostAddress = ConvertFrom-XmipDeployNumber -Number ($range.First + 1)
    for ([int] $index = 0; $index -lt $listed.Count; $index++) {
        $listed[$index]['address'] = ConvertFrom-XmipDeployNumber -Number (
            $range.First + 2 + $index)
    }
    [string] $controller = Get-TomlValue -Node $environment -Name 'domain_controller' -Default ''
    $named = $listed | Where-Object { $_.name -eq $controller } | Select-Object -First 1
    [string] $dnsServer = if ($named) { $named.address } else { $hostAddress }
    [string] $environmentName = "Xmip-$Name"
    [string] $gateway = Get-TomlValue -Node $environment -Name 'gateway' -Default ''
    [bool] $online = @($listed | Where-Object { $_.online }).Count -gt 0
    [hashtable] $common = @{
        environment = $environmentName
        root = $Facts.Root
        secretPath = if ($windows.Count -gt 0) { $Facts.Secret } else { '' }
        linuxAccount = $Facts.LinuxAccount
        domainName = Get-TomlValue -Node $environment -Name 'domain' -Default 'xmip.test'
        network = @{
            name = $environmentName
            bridge = "virbr-$($Name.ToLowerInvariant())"
            prefix = $Facts.Network
            gateway = $hostAddress
            prefixLength = [int] $range.Length
            dnsServer = $dnsServer
            enableNat = $online -and -not $gateway
        }
    }
    [Collections.Generic.List[hashtable]] $machines = @()
    foreach ($machine in $listed) {
        [hashtable] $value = $common.Clone()
        $value['name'] = $machine.machine
        $value['address'] = $machine.address
        $value['description'] = $machine.description
        $value['network'] = $common.network.Clone()
        if (-not $machine.online) {
            $value['network']['gateway'] = ''
        }
        $value['image'] = ConvertTo-XmipTomlTable -Node (Get-TomlValue -Node $images -Name (
                $machine.os))
        $value['image']['path'] = $Facts.Images[$machine.os]
        $value['memoryGB'] = [int] $machine.memory_gb
        [hashtable] $sized = @{ name = $machine.machine; memory_gb = $machine.memory_gb
            dynamic_memory = $machine.dynamic_memory }
        $value['dynamicMemory'] = Get-XmipDeployDynamicMemory -Machine $sized -Hypervisor (
            $Hypervisor) -Family $machine.family
        $value['cpu'] = [int] $machine.cpu
        $value['diskGB'] = [int] $machine.disk_gb
        $value['pool'] = $environmentName
        $machines.Add($value)
    }
    # Xmip Storage first, which every other node reaches, then the file's
    # order: what the node steps install in.
    [hashtable[]] $nodes = @(@($listed | Where-Object { $_.kind -eq 'node' -and $_.storage }) +
        @($listed | Where-Object { $_.kind -eq 'node' -and -not $_.storage }) | ForEach-Object {
            @{ node = $_.name; machine = @{ name = $_.machine; address = $_.address
                    family = $_.family } }
        })
    [hashtable] $read = @{
        Name = $environmentName
        Technology = $Technology
        Hypervisor = $Hypervisor
        Template = Split-Path -Path $template -Parent
        Common = $common
        Machines = $machines.ToArray()
        Listed = $listed
        Names = @(Get-XmipDeployName -Listed $listed -Cluster $Name)
        NameServer = if ($named) {
            @{ name = $named.machine; address = $named.address; family = $named.family }
        }
        Nodes = $nodes
        Placed = (@($nodes | ForEach-Object { $_.node }) -join ',')
        Cluster = $Name
        File = $File
        Sha256 = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant()
        Host = $Facts.WindowsHost
        Tools = $Facts.Tools
    }
    Add-XmipDeployDomain -Environment $environment -Read $read
    Add-XmipDeployGateway -Environment $environment -Read $read -Uplink $Facts.Uplink
    if ($nodes.Count -gt 0) {
        $read['Node'] = Get-XmipDeployNodeValue -Environment $environment -Facts $Facts -Run (
            $Run) -Read $read
    }
    Add-XmipDeployFarEnd -Read $read -Facts $Facts
    return $read
}

function Get-XmipDeployNodeValue {
    <#
        .SYNOPSIS
            What every node of the environment is given: the cluster's file,
            this host's xmip-service that slices and signs it, the authority
            that signs and the folder of each node's certificate, the far
            ends its Send Ports put on, who operates it, and the package for
            each family a node runs on.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment,

        [Parameter(Mandatory)]
        [hashtable] $Facts,

        [Parameter(Mandatory)]
        [string] $Run,

        [Parameter(Mandatory)]
        [hashtable] $Read
    )

    # The far ends a Send Port puts on, the receivers in their order, each
    # Receive Location listening on its node for the senders' push (ADR-0028,
    # amendment 2026-11-22).
    $farEnds = Get-TomlValue -Node $Environment -Name 'far_ends' -Default $null
    [string[]] $receivers = @(Get-TomlValue -Node $farEnds -Name 'receivers' -Default @())
    [hashtable] $given = @{
        configuration = $Read.File
        slicer = $Facts.Slicer
        authority = $Facts.Authority
        identity = $Facts.Identity
        farEnd = $receivers -join ','
        listen = $receivers.Count -gt 0
        # Who operates the nodes, each listed among every slice's [operate]
        # operators (xmip-service --slice --operators).
        operators = @($Facts.Operators | Where-Object { $_ }) -join ','
        slices = Join-Path $Run 'slice'
    }
    [hashtable] $packages = @{ Linux = @{}; Windows = @{} }
    foreach ($family in @($Facts.Packages.Keys)) {
        [hashtable] $package = $Facts.Packages[$family].Clone()
        $package['file'] = 'xmip' + [IO.Path]::GetExtension($package.path)
        # The module libraries as one file, which msdsc sends beside the
        # package: a zip, empty where the cluster names none, written once the
        # run holds its lock (Invoke-XmipDeployStep).
        $package['archive'] = Join-Path -Path $Run -ChildPath (
            "modules-$($family.ToLowerInvariant()).zip")
        $packages[$family] = $package
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

function Get-XmipDeployName {
    <#
        .SYNOPSIS
            The names the environment adds to its machines' own: each node
            and each far end at its machine's address, found by its own name
            (ADR-0028, amendment 2026-11-22), and the cluster at every
            address that runs one of its nodes.

        .PARAMETER Listed
            The machines, Resolve-XmipDeployMachine's, each with its address.

        .PARAMETER Cluster
            The cluster's name.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable[]] $Listed,

        [Parameter(Mandatory)]
        [string] $Cluster
    )

    foreach ($machine in @($Listed | Where-Object { $_.kind -ne 'machine' })) {
        @{ name = $machine.name; addresses = @($machine.address) }
    }
    [string[]] $running = @($Listed | Where-Object { $_.kind -eq 'node' } |
            ForEach-Object { $_.address })
    if ($running.Count -gt 0) {
        @{ name = $Cluster; addresses = $running }
    }
}
