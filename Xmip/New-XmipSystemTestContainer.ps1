#requires -Version 7.7.0

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    One container of a run of the System Tests: its configuration's folder,
    the ports it publishes, and the container made and started.

.DESCRIPTION
    Start-XmipSystemTestContainer makes one for each node and far end of the
    cluster file (ADR-0028, amendment 2026-11-25).

    Style: doc/governance/powershell-style.md
#>

function New-XmipSystemTestContainer {
    <#
        .SYNOPSIS
            Makes one container on the run's network, found there by its
            name, the programs mounted read-only and its configuration copied
            in, every port it listens on published on this computer's
            loopback, and starts it; answers each listener, <name>:<port>, at
            the address its port is published on.

        .PARAMETER Tool
            The container tool's path.

        .PARAMETER Image
            The image it runs.

        .PARAMETER Network
            The run's network.

        .PARAMETER Program
            The folder of the programs, mounted at /xmip/bin.

        .PARAMETER Made
            The node or far end: name, container, config, ports and command.

        .PARAMETER Port
            A free port on this computer for each of its ports, in order.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string] $Tool,

        [Parameter(Mandatory)]
        [string] $Image,

        [Parameter(Mandatory)]
        [string] $Network,

        [Parameter(Mandatory)]
        [string] $Program,

        [Parameter(Mandatory)]
        [hashtable] $Made,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [int[]] $Port
    )

    # A node outside a service manager is told its endpoints' folder; the
    # container's /run is root's and written by no one else (ADR-0014,
    # amendment 2026-11-15).
    [string[]] $argument = @('create', '--name', $Made.container, '--network', $Network,
        '--network-alias', $Made.name, '--hostname', $Made.name, '--stop-signal', 'SIGINT',
        '-v', "${Program}:/xmip/bin:ro", '-e', 'XMIP_AUDIT_DIRECTORY=/xmip/config/audit',
        '-e', 'XMIP_RUNTIME_DIRECTORY=/run')
    [Collections.Specialized.OrderedDictionary] $published = [ordered] @{}
    for ([int] $at = 0; $at -lt @($Made.ports).Count; $at++) {
        [int] $own = @($Made.ports)[$at]
        $published["$($Made.name):$own"] = "127.0.0.1:$($Port[$at])"
        $argument += @('-p', "127.0.0.1:$($Port[$at]):$own")
    }
    $null = Invoke-XmipContainerTool -Tool $Tool -Argument ($argument + $Image + $Made.command)
    # Copied into /xmip, which the mount made: a copy from Windows keeps no
    # mode, and a program copied so would not run, so the programs are
    # mounted.
    $null = Invoke-XmipContainerTool -Tool $Tool -Argument @(
        'cp', $Made.config, "$($Made.container):/xmip")
    $null = Invoke-XmipContainerTool -Tool $Tool -Argument @('start', $Made.container)
    return $published
}

function New-XmipContainerFolder {
    <#
        .SYNOPSIS
            The folder a container's configuration is copied from, made anew
            under -State as <name>/config: its certificate, node.pem, node.key
            and anchors.pem, in -Into, and every module library; its path.

        .PARAMETER State
            The containers' own folder.

        .PARAMETER Name
            The node or far end.

        .PARAMETER Identity
            The folder of every certificate, one folder each by name.

        .PARAMETER Into
            Where in the configuration its certificate goes: tls for a node,
            as its slice names them, . for a far end.

        .PARAMETER Modules
            The folder of the module libraries a node is given, if any.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $State,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Identity,

        [Parameter(Mandatory)]
        [string] $Into,

        [Parameter()]
        [string] $Modules = ''
    )

    [string] $config = Join-Path $State "$Name/config"
    [string] $own = Split-Path -Path $config -Parent
    Remove-Item -LiteralPath $own -Recurse -Force -ErrorAction Ignore
    [string] $tls = Join-Path $config $Into
    $null = New-Item -ItemType Directory -Path $tls, (Join-Path $config 'audit') -Force
    foreach ($leaf in 'node.pem', 'node.key', 'anchors.pem') {
        Copy-Item -LiteralPath (Join-Path $Identity "$Name/$leaf") -Destination $tls
    }
    if ($Modules -and (Test-Path -LiteralPath $Modules -PathType Container)) {
        Get-ChildItem -LiteralPath $Modules -File | Copy-Item -Destination $config
    }
    return $config
}

function Get-XmipListeningPort {
    <#
        .SYNOPSIS
            Every port a program's configuration listens on, as the program
            itself says it (--listening): each is published, and the roll
            asks the one it reaches.

        .PARAMETER Program
            xmip-service or xmip-system-test-external, built for this host.

        .PARAMETER Configuration
            What the program is given as --configuration.
    #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Program,

        [Parameter(Mandatory)]
        [string] $Configuration
    )

    [string[]] $said = @(& $Program --configuration $Configuration --listening 2>&1 |
            ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) {
        throw "FAILED: $Program --listening exited $LASTEXITCODE`: $($said -join ' ')"
    }
    return [int[]] @($said | Where-Object { $_ -match '^(\d+)/tcp\b' } |
            ForEach-Object { [int] ($_ -replace '/.*$', '') } | Sort-Object -Unique)
}
