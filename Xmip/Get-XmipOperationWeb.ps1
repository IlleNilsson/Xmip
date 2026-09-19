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

    $url = @{
        CommandLine = $line
        Name        = 'Kestrel:Endpoints:Http:Url'
    }

    return [PSCustomObject]@{
        PSTypeName = 'Xmip.Web'
        Id         = $Process.Id
        Url        = Read-XmipOperationWebArgument @url
        Surface    = if ([string]::IsNullOrEmpty($surface)) { 'configured' } else { $surface }
        Snapshot   = Read-XmipOperationWebArgument -CommandLine $line -Name 'Xmip:Snapshot'
        StartTime  = $Process.StartTime
    }
}

function Read-XmipOperationWebArgument {
    <#
        .SYNOPSIS
            The value of one `--Name=value` argument on a web host's command
            line, quotes removed; empty when absent. Pure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $CommandLine,

        [Parameter(Mandatory)]
        [string] $Name
    )

    [string] $pattern = '--' + [regex]::Escape($Name) + '=("[^"]*"|\S+)'

    if ($CommandLine -match $pattern) {
        return $Matches[1].Trim('"')
    }

    return ''
}
