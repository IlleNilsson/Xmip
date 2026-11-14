#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipOperationWeb {
    <#
        .SYNOPSIS
            The Xmip web monitors running on this machine: address, the
            surface each reads and where.

        .DESCRIPTION
            A web host is a process running the GUI's own web executable; what
            it reads is on its command line — the Kestrel address, and the
            surface of each cluster it holds (ADR-0052 clause 3: chosen, never
            guessed), the local endpoint of a node or the path of a snapshot.
            Nothing running means no output.

        .EXAMPLE
            Get-XmipOperationWeb
    #>
    [CmdletBinding()]
    [OutputType('Xmip.Web')]
    param()

    $ErrorActionPreference = 'Stop'
    $layout = Get-XmipEssentialsLayout

    [System.Diagnostics.Process[]] $hosts = @(
        Get-XmipEssentialsProcess -Name 'xmip-gui-web' -Path $layout.Web
    )

    foreach ($process in $hosts) {
        ConvertTo-XmipOperationWeb -Process $process
    }
}

function ConvertTo-XmipOperationWeb {
    <#
        .SYNOPSIS
            One web host process as the Xmip.Web object the web cmdlets emit.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.Web')]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process
    )

    [string] $line = try { "$($Process.CommandLine)" } catch { '' }

    # One surface per cluster, each of its own kind, as
    # Get-XmipOperationWebClusterArgument wrote them (the design approved
    # 2026-11-12, section 3.4); else the one surface a line named the plain
    # way; else the host reads its gui.toml.
    $read = @{
        CommandLine = $line
        Every       = $true
    }
    [string[]] $kinds = @(Read-XmipOperationWebArgument @read -Name 'Xmip:Clusters:*:Surface')
    [string] $surface = if ($kinds.Count -gt 0) {
        $kinds -join ', '
    }
    else {
        Read-XmipOperationWebArgument -CommandLine $line -Name 'Xmip:Surface'
    }

    $url = @{
        CommandLine = $line
        Name        = 'Kestrel:Endpoints:Http:Url'
    }

    return [PSCustomObject]@{
        PSTypeName = 'Xmip.Web'
        Id         = $Process.Id
        Url        = Read-XmipOperationWebArgument @url
        Surface    = if ([string]::IsNullOrEmpty($surface)) { 'configured' } else { $surface }
        Local      = @(Read-XmipOperationWebArgument @read -Name 'Xmip:Clusters:*:Local')
        Snapshot   = @(
            Read-XmipOperationWebArgument @read -Name 'Xmip:Clusters:*:Snapshot'
            Read-XmipOperationWebArgument -CommandLine $line -Name 'Xmip:Snapshot' |
                Where-Object { $_ }
        )
        StartTime  = $Process.StartTime
    }
}

function Read-XmipOperationWebArgument {
    <#
        .SYNOPSIS
            The value of one `--Name=value` argument on a web host's command
            line, quotes removed; empty when absent. Pure.

        .DESCRIPTION
            A host may be told several of one thing — one surface per cluster,
            as --Xmip:Clusters:0:Local and --Xmip:Clusters:1:Snapshot (ADR-0052,
            amendment 2026-11-13). -Every reads them all, in the order they
            were written; without it the first is read.

        .PARAMETER CommandLine
            The host process's command line.

        .PARAMETER Name
            The key, without its leading dashes. A * in it stands for an
            index: Xmip:Clusters:*:Snapshot is each cluster's snapshot.

        .PARAMETER Every
            Read every value the key names.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $CommandLine,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [switch] $Every
    )

    [string] $key = [regex]::Escape($Name).Replace('\*', '\d+')

    # The whole argument quoted, as a path with a space in it is passed, or
    # its value alone, or neither.
    [string] $pattern = "`"--$key=(?<v>[^`"]*)`"|--$key=(?<v>`"[^`"]*`"|\S+)"

    if (-not $Every) {
        if ($CommandLine -match $pattern) {
            return $Matches['v'].Trim('"')
        }

        return ''
    }

    return @([regex]::Matches($CommandLine, $pattern) |
            ForEach-Object { $_.Groups['v'].Value.Trim('"') })
}
