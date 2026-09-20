#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipOperationWeb {
    <#
        .SYNOPSIS
            The Xmip web monitors running on this machine: address, the
            surface each reads and where.

        .DESCRIPTION
            A web host is a process running the GUI's own web executable; what
            it reads is on its command line — the Kestrel address, the surface
            (ADR-0052 clause 3: chosen, never guessed) and the snapshot path
            when the surface is a snapshot. Nothing running means no output.

        .EXAMPLE
            Get-XmipOperationWeb
    #>
    [CmdletBinding()]
    [OutputType('Xmip.Web')]
    param()

    $ErrorActionPreference = 'Stop'
    $layout = Get-XmipPlaygroundLayout

    [System.Diagnostics.Process[]] $hosts = @(
        Get-XmipPlaygroundProcess -Name 'xmip-gui-web' -Path $layout.Web
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
    [string] $surface = Read-XmipOperationWebArgument -CommandLine $line -Name 'Xmip:Surface'

    # One key for one snapshot, an indexed key each for several: a host may
    # hold a cluster per snapshot (ADR-0052, amendment 2026-09-20).
    $read = @{
        CommandLine = $line
        Name        = 'Xmip:Snapshot'
        Every       = $true
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
        Snapshot   = @(Read-XmipOperationWebArgument @read)
        StartTime  = $Process.StartTime
    }
}

function Read-XmipOperationWebArgument {
    <#
        .SYNOPSIS
            The value of one `--Name=value` argument on a web host's command
            line, quotes removed; empty when absent. Pure.

        .DESCRIPTION
            A host may be told several of one thing — one snapshot per cluster,
            as --Xmip:Snapshot:0 and --Xmip:Snapshot:1 (ADR-0052, amendment
            2026-09-20). -Every reads them all, in the order they were written,
            and reads a plain --Name= too; without it the plain key alone is
            read, as it always was.

        .PARAMETER CommandLine
            The host process's command line.

        .PARAMETER Name
            The key, without its leading dashes.

        .PARAMETER Every
            Read every value of the key, indexed ones included.
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

    [string] $key = [regex]::Escape($Name)
    [string] $value = '=("[^"]*"|\S+)'
    [string] $pattern = if ($Every) { "--$key(?::\d+)?$value" } else { "--$key$value" }

    if (-not $Every) {
        if ($CommandLine -match $pattern) {
            return $Matches[1].Trim('"')
        }

        return ''
    }

    return @([regex]::Matches($CommandLine, $pattern) |
            ForEach-Object { $_.Groups[1].Value.Trim('"') })
}
