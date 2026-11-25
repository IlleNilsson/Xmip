#requires -Version 7.7.0

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    The container tool this host runs the System Tests' containers with, the
    one way the module runs it, and what each container is made from.

.DESCRIPTION
    Start-XmipTest -Container runs every node and far end of the cluster file
    in a Linux container of its own (ADR-0015 and ADR-0028, amendments
    2026-11-25): on Windows in WSL containers, wslc, Windows' own; on Linux
    in Podman, the system's own, rootless. The two take the same verbs and
    switches, so nothing else in the module knows which it runs.

    Style: doc/governance/powershell-style.md
#>

# The tool each host runs Linux containers with, and what installs it where
# it is absent (the owner, 2026-11-24: WSL containers or containerd on
# Windows, Podman on Linux). containerd runs Windows containers, which the
# Linux programs a container is given do not run in.
[hashtable] $script:XmipContainerTool = @{
    Windows = @{
        Tool    = 'wslc'
        Install = 'wsl --update, which brings WSL containers with WSL 3.0.1 or later'
    }
    Linux   = @{
        Tool    = 'podman'
        Install = ('the system''s own package, rootless: sudo apt install podman uidmap, or ' +
            'sudo dnf install podman')
    }
}

function Get-XmipContainerTool {
    <#
        .SYNOPSIS
            The path of the container tool this host runs Linux containers
            with: wslc on Windows, podman on Linux. REFUSED, by throwing, on
            any other host and where the tool is absent, naming what
            installs it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    [string] $family = if ($IsWindows) { 'Windows' } elseif ($IsLinux) { 'Linux' } else { '' }

    if ($family -eq '') {
        throw ('REFUSED: running as containers takes WSL containers on Windows or Podman on ' +
            'Linux, and this host is neither.')
    }

    [hashtable] $known = $script:XmipContainerTool[$family]
    $found = Get-Command -Name $known.Tool -CommandType Application -ErrorAction Ignore |
        Select-Object -First 1

    if ($null -eq $found) {
        throw ("REFUSED: running as containers on $family takes $($known.Tool), which this " +
            "host has not: $($known.Install).")
    }

    return $found.Source
}

function Invoke-XmipContainerTool {
    <#
        .SYNOPSIS
            Runs the container tool with the arguments given and answers its
            lines; FAILED, by throwing, with what it said where it exits
            otherwise than 0.

        .PARAMETER Tool
            The tool's path, Get-XmipContainerTool's.

        .PARAMETER Argument
            Everything after the tool's name: its verb first.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Tool,

        [Parameter(Mandatory)]
        [string[]] $Argument
    )

    # wsl's tools write UTF-16 unless told otherwise; podman reads nothing of it.
    [string] $was = $env:WSL_UTF8
    $env:WSL_UTF8 = '1'

    try {
        [string[]] $said = @(& $Tool @Argument 2>&1 | ForEach-Object { "$_" })
    }
    finally {
        $env:WSL_UTF8 = $was
    }

    if ($LASTEXITCODE -ne 0) {
        [string] $words = @($said | Where-Object { $_.Trim() -ne '' }) -join ' '
        [string] $named = Split-Path -Path $Tool -Leaf
        throw "FAILED: $named $($Argument[0]) exited $LASTEXITCODE`: $words"
    }

    return $said
}

function Test-XmipContainerThere {
    <#
        .SYNOPSIS
            Whether the container tool finds what -Argument inspects: a
            container, or a network. Read from its answer, a JSON array of
            what it found: podman answers otherwise than 0 for one that is not
            there, and so does wslc for a container, but wslc 5.0.1 answers a
            network that is not there with 0, its words and [].

        .PARAMETER Tool
            The tool's path.

        .PARAMETER Argument
            inspect and its name, or network inspect and its name.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Tool,

        [Parameter(Mandatory)]
        [string[]] $Argument
    )

    try {
        [string[]] $said = @(Invoke-XmipContainerTool -Tool $Tool -Argument $Argument)
    }
    catch {
        Write-Verbose "$($Argument -join ' '): $($_.Exception.Message)"
        return $false
    }

    # The array begins at the first line that opens one; words before it
    # are the tool's own.
    [int] $from = [Array]::FindIndex($said, [Predicate[string]] {
            param($line) $line.TrimStart().StartsWith('[') })
    if ($from -lt 0) {
        return $false
    }
    [string] $array = $said[$from..($said.Count - 1)] -join "`n"
    try {
        $found = ConvertFrom-Json -InputObject $array -NoEnumerate
    }
    catch {
        Write-Verbose "$($Argument -join ' '): $($_.Exception.Message)"
        return $false
    }
    return @($found).Count -gt 0
}

function Get-XmipContainerAddress {
    <#
        .SYNOPSIS
            A container's address on a network, as the container tool says
            it: both tools answer inspect with Docker's own shape.

        .PARAMETER Tool
            The tool's path.

        .PARAMETER Container
            The container.

        .PARAMETER Network
            The network it is on.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Tool,

        [Parameter(Mandatory)]
        [string] $Container,

        [Parameter(Mandatory)]
        [string] $Network
    )

    [string[]] $said = @(Invoke-XmipContainerTool -Tool $Tool -Argument @('inspect', $Container))
    $networks = @(ConvertFrom-Json -InputObject ($said -join "`n"))[0].NetworkSettings.Networks
    [string] $address = $networks.$Network.IPAddress
    if ($address -eq '') {
        throw "FAILED: the container $Container has no address on $Network."
    }
    return $address
}

function Get-XmipFreePort {
    <#
        .SYNOPSIS
            Ports no listener on this computer's loopback holds, -Count of
            them, each different: every one is held open until all are found.

        .PARAMETER Count
            How many.
    #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory)]
        [int] $Count
    )

    [Collections.Generic.List[Net.Sockets.TcpListener]] $held = @()
    try {
        for ([int] $one = 0; $one -lt $Count; $one++) {
            $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
            $listener.Start()
            $held.Add($listener)
        }
        return [int[]] @($held | ForEach-Object { $_.LocalEndpoint.Port })
    }
    finally {
        $held | ForEach-Object { $_.Stop() }
    }
}

function Get-XmipContainerImage {
    <#
        .SYNOPSIS
            The image every container of the run runs, as the cluster file's
            [environment.container] image names it; REFUSED, by throwing,
            where it names none.

        .DESCRIPTION
            The image is the end user's (ADR-0015, amendment 2026-11-23), and
            the System Tests' file names the one its tests run: a Linux whose
            C library runs the programs built for Linux. The container tool
            pulls it where it has none.

        .PARAMETER Content
            The cluster file, as Read-XmipToml reads it.

        .PARAMETER File
            The cluster file's path, as a refusal names it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Content,

        [Parameter(Mandatory)]
        [string] $File
    )

    $environment = Get-TomlValue -Node $Content -Name 'environment' -Default $null
    $container = Get-TomlValue -Node $environment -Name 'container' -Default $null
    [string] $image = Get-TomlValue -Node $container -Name 'image' -Default ''

    if ($image.Trim() -eq '') {
        throw ("REFUSED: $File names no image a container runs: [environment.container] " +
            'image, a Linux image the container tool pulls where it has none.')
    }

    return $image
}

function Get-XmipContainerBuild {
    <#
        .SYNOPSIS
            The Linux programs a container is given, as a Linux machine is
            given them (Get-XmipBuiltProgram): Service, xmip-service; FarEnd,
            the far ends' program; Modules, the module libraries' folder.
            REFUSED, by throwing, where one is not there, naming what builds
            it.

        .PARAMETER Estate
            The estate's root.

        .PARAMETER Content
            The cluster file, as Read-XmipToml reads it: whether its
            [[modules]] name libraries.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Content
    )

    [hashtable] $built = Get-XmipBuiltProgram -Estate $Estate -Family Linux
    [string] $where = if ($IsWindows) { ' in the WSL guest' } else { '' }
    [string] $how = "$($built.Build)$where"

    if (-not (Test-Path -LiteralPath $built.Service -PathType Leaf)) {
        throw "REFUSED: a container runs $($built.Service), which is not there: $how."
    }

    if (-not (Test-Path -LiteralPath $built.FarEnd -PathType Leaf)) {
        throw ("REFUSED: a far end's container runs $($built.FarEnd), which is not there: " +
            'the System Tests'' xmip-system-test-external built for Linux beside it.')
    }

    [bool] $modules = @(Get-TomlValue -Node $Content -Name 'modules' -Default @()).Count -gt 0

    if ($modules -and -not (Test-Path -LiteralPath $built.Modules -PathType Container)) {
        throw ("REFUSED: the cluster file's [[modules]] name module libraries, which a " +
            "container is given from $($built.Modules), which is not there: their libraries " +
            'built for Linux.')
    }

    return $built
}
