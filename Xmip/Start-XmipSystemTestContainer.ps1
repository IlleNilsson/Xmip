#requires -Version 7.7.0

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    The containers a run of the System Tests runs in: one for each node and
    each far end of the cluster file, made, started and taken away.

.DESCRIPTION
    Start-XmipTest -Container (ADR-0015 and ADR-0028, amendments 2026-11-25):
    every node and far end of the Reference Environment runs in a
    Linux container of its own, on a network of the cluster's, found there by
    its name; each is given what a Linux machine of a deployed environment is
    given, its slice signed and its certificates issued as Deploy-XmipEnvironment
    gives them, under the System Tests' own authority. The roll then reads
    them as it reads virtual machines, each at its container's address, and
    reaches the listeners it asks where the container tool published them on
    this computer, which reaches no container's own address.

    Style: doc/governance/powershell-style.md
#>

# How long a node a container started is waited for until it is ready, asked
# each time it publishes (xmip-service --readiness): the bound a deployment
# waits for one (deploy/dsc/msdsc/environment/node.dsc.yaml, ready).
[int] $script:XmipContainerReady = 180

function Start-XmipSystemTestContainer {
    <#
        .SYNOPSIS
            Makes and starts a container for each node and far end of the
            Reference Environment, what an earlier run of the cluster
            left taken away first; returns what the roll reads them by, as
            Read-XmipDeployedEnvironment returns a deployed environment.

        .DESCRIPTION
            Returns Nodes and FarEnds, each name at its container's address;
            Published, each listener, <name>:<port>, at the address on this
            computer its port is published on; and Operator, the folder of
            the operator certificate the roll asks them with. Each node is
            waited for until it says it is ready. The containers, the network
            and the tool are recorded in container/<cluster>/containers.toml
            under -Area, which Remove-XmipSystemTestContainer reads.

        .PARAMETER Cluster
            The run's cluster.

        .PARAMETER Area
            The run's area, where the System Tests' authority is kept and the
            containers' own folder, container/<cluster>, is made.

        .PARAMETER Slicer
            This host's xmip-service, which slices and signs each node's
            configuration and says what it listens on.

        .PARAMETER Listener
            This host's xmip-system-test-external, which says what a far end
            listens on.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter(Mandatory)]
        [string] $Area,

        [Parameter(Mandatory)]
        [string] $Slicer,

        [Parameter(Mandatory)]
        [string] $Listener
    )

    [string] $tool = Get-XmipContainerTool
    $layout = Get-XmipSystemTestLayout
    [string] $file = $layout.Configuration
    $content = Read-XmipToml -Path $file
    [string] $image = Get-XmipContainerImage -Content $content -File $file
    [hashtable] $built = Get-XmipContainerBuild -Estate $layout.Root -Content $content
    Remove-XmipSystemTestContainer -Cluster $Cluster -Area $Area

    # Every node and far end the file names, none of the machines of their
    # own: Xmip Storage first, which every other node reaches, then the
    # file's order, as an environment installs them.
    [hashtable[]] $listed = @(Resolve-XmipDeployMachine -Cluster $content)
    [hashtable[]] $farEnds = @($listed | Where-Object { $_.kind -eq 'far end' })
    [hashtable[]] $nodes = @(@($listed | Where-Object { $_.kind -eq 'node' -and $_.storage }) +
        @($listed | Where-Object { $_.kind -eq 'node' -and -not $_.storage }))
    [string] $state = Join-Path $Area "container/$Cluster"
    [hashtable] $facts = @{
        Authority = Join-Path $Area 'authority'
        Identity  = Join-Path $state 'identity'
        Operator  = Join-Path $state 'operator'
        Operators = @("CN=$([Environment]::UserName)")
    }
    $null = Initialize-XmipSystemTestAuthority -Folder $facts.Authority -Confirm:$false
    [hashtable] $read = @{
        Cluster = $Cluster
        File    = $file
        Nodes   = @($nodes | ForEach-Object { @{ node = $_.name } })
        FarEnds = @($farEnds | ForEach-Object { @{ name = $_.name } })
    }
    Initialize-XmipDeployIdentity -Read $read -Facts $facts

    # One copy of the programs for every container, mounted read-only, so a
    # later build never changes what a running container runs; emptied
    # first, since a copy over an earlier run's hard link writes the build.
    [string] $program = Join-Path $state 'program'
    Remove-Item -LiteralPath $program -Recurse -Force -ErrorAction Ignore
    $null = New-Item -ItemType Directory -Path $program -Force
    foreach ($source in $built.Service, $built.FarEnd) {
        [string] $placed = Join-Path $program (Split-Path -Path $source -Leaf)
        Copy-XmipSystemTestImage -Source $source -Image $placed
    }

    # Each node's slice, as a deployment slices it: every Receive Location
    # listening on its node, every Send Port bound to the receiver of its
    # turn (deploy/dsc/msdsc/environment/EnvironmentSlice.ps1).
    [string] $templates = Join-Path $layout.Root 'deploy/dsc/msdsc/environment'
    . (Join-Path $templates 'Program.ps1')
    . (Join-Path $templates 'EnvironmentSlice.ps1')
    $environment = Get-TomlValue -Node $content -Name 'environment' -Default $null
    $sides = Get-TomlValue -Node $environment -Name 'far_ends' -Default $null
    [string[]] $receivers = @(Get-TomlValue -Node $sides -Name 'receivers' -Default @())
    [hashtable] $slicing = @{
        program = $Slicer; configuration = $file; cluster = $Cluster
        authority = $facts.Authority; bind = $receivers -join ','; listen = $receivers.Count -gt 0
        nodes = @($nodes | ForEach-Object { $_.name }) -join ','
        operators = $facts.Operators -join ','
    }
    Initialize-XmipAudit
    Initialize-XmipRuntimeDirectory
    [Collections.Generic.List[hashtable]] $made = @()
    foreach ($far in $farEnds) {
        [string] $config = New-XmipContainerFolder -State $state -Name $far.name -Identity (
            $facts.Identity) -Into '.'
        $made.Add(@{ name = $far.name; kind = 'external'; config = $config
                ports = @(Get-XmipListeningPort -Program $Listener -Configuration $config)
                command = @("/xmip/bin/$(Split-Path -Path $built.FarEnd -Leaf)", '--name',
                    $far.name, '--serve', '--configuration', '/xmip/config') })
    }
    foreach ($node in $nodes) {
        [string] $config = New-XmipContainerFolder -State $state -Name $node.name -Identity (
            $facts.Identity) -Into 'tls' -Modules $built.Modules
        [hashtable] $sliced = $slicing + @{ node = $node.name; into = $config }
        Set-EnvironmentSlice -Instance $sliced -Confirm:$false
        [string] $slice = Join-Path $config 'node.xmip'
        $made.Add(@{ name = $node.name; kind = 'node'; config = $config
                ports = @(Get-XmipListeningPort -Program $Slicer -Configuration $slice)
                command = @("/xmip/bin/$(Split-Path -Path $built.Service -Leaf)",
                    '--configuration', '/xmip/config/node.xmip', '--console') })
    }

    # Recorded before anything is made, so whatever a failure leaves is
    # taken away by the next start or by Stop-XmipTest.
    [hashtable] $common = @{ Tool = $tool; Image = $image; Network = "Xmip-$Cluster"
        Program = $program }
    foreach ($one in $made) {
        $one['container'] = "xmip-system-test-$Cluster-$($one.kind)-$($one.name)"
    }
    Write-XmipToml -Path (Join-Path $state 'containers.toml') -Value ([ordered] @{
            tool = $tool; network = $common.Network
            containers = @($made | ForEach-Object { $_.container }) })
    $null = Invoke-XmipContainerTool -Tool $tool -Argument @('network', 'create', $common.Network)
    [int[]] $free = @(Get-XmipFreePort -Count (@($made | ForEach-Object { $_.ports }).Count))
    [hashtable] $deployed = @{ Operator = $facts.Operator; Published = [ordered] @{}
        Nodes = [ordered] @{}; FarEnds = [ordered] @{} }
    [int] $next = 0
    foreach ($one in $made) {
        [int[]] $hosted = @($free | Select-Object -Skip $next -First $one.ports.Count)
        $next += $one.ports.Count
        $at = New-XmipSystemTestContainer @common -Made $one -Port $hosted
        foreach ($key in $at.Keys) {
            $deployed.Published[$key] = $at[$key]
        }
    }

    foreach ($one in $made) {
        [string] $table = if ($one.kind -eq 'node') { 'Nodes' } else { 'FarEnds' }
        $deployed[$table][$one.name] = Get-XmipContainerAddress -Tool $tool -Container (
            $one.container) -Network $common.Network
    }
    # Each node waited for until it says it is ready, Xmip Storage first, as
    # a deployment waits for each (ADR-0056, amendment 2026-11-23).
    foreach ($one in @($made | Where-Object { $_.kind -eq 'node' })) {
        $null = Invoke-XmipContainerTool -Tool $tool -Argument @('exec', $one.container,
            $one.command[0], '--configuration', '/xmip/config/node.xmip', '--readiness',
            '--within', "$script:XmipContainerReady")
    }
    return $deployed
}

function Remove-XmipSystemTestContainer {
    <#
        .SYNOPSIS
            Takes away the containers and the network a run of the cluster
            made, as its containers.toml under -Area records them, and the
            record; nothing where there is none.

        .DESCRIPTION
            Stop-XmipTest calls it once it has stopped a roll, and
            Start-XmipSystemTestContainer before it makes the cluster's
            containers again. A container or network already gone is not a
            fault; one the tool will not take away is.

        .PARAMETER Cluster
            The run's cluster.

        .PARAMETER Area
            The run's area.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter(Mandatory)]
        [string] $Area
    )

    [string] $path = Join-Path $Area "container/$Cluster/containers.toml"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return
    }
    $read = Read-XmipToml -Path $path
    [string] $tool = Get-TomlValue -Node $read -Name 'tool'
    [string] $network = Get-TomlValue -Node $read -Name 'network'
    [string[]] $containers = @(Get-TomlValue -Node $read -Name 'containers' -Default @())
    if (-not $PSCmdlet.ShouldProcess("cluster $Cluster's containers", 'Remove')) {
        return
    }
    [string[]] $taken = @($containers | Where-Object {
            Test-XmipContainerThere -Tool $tool -Argument @('inspect', $_) })
    if ($taken.Count -gt 0) {
        $null = Invoke-XmipContainerTool -Tool $tool -Argument (@('rm', '-f') + $taken)
    }
    if (Test-XmipContainerThere -Tool $tool -Argument @('network', 'inspect', $network)) {
        $null = Invoke-XmipContainerTool -Tool $tool -Argument @('network', 'rm', $network)
    }
    Remove-Item -LiteralPath $path -Force
}
