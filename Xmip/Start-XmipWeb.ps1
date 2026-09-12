#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Start-XmipWeb {
    <#
        .SYNOPSIS
            Starts the Xmip web monitor, detached, over the surface you name.

        .DESCRIPTION
            The web surface is monitoring only (ADR-0014): it reads a snapshot
            a roll or a node published and shows the cluster, the drill-down
            and the history. This starts it as a background process and hands
            it the address and, when given, the snapshot to read — the surface
            is chosen on the command line, never guessed (ADR-0052 clause 3).
            Without -Snapshot the host reads what its own xmip.gui.toml says.

            It launches the built executable when one is present and falls back
            to `dotnet run` from source otherwise. It binds to 127.0.0.1 by
            default rather than localhost, because a browser that cached HSTS for
            localhost from another app silently forces https and the plain-http
            server then looks dead. Get-XmipWeb lists what is running and
            Stop-XmipWeb ends it.

        .PARAMETER Snapshot
            The snapshot file to monitor. Bound from the pipeline, so a
            Start-XmipTest -PassThru object names it.

        .PARAMETER Url
            Where to bind. Defaults to http://127.0.0.1:5087. Use
            http://0.0.0.0:5087 to reach it from another device on the network
            (the firewall must also allow the port).

        .PARAMETER FromSource
            Run `dotnet run` from the project rather than the built executable —
            for development, when the source is newer than the last build.

        .PARAMETER PassThru
            Return the Xmip.Web object for the host started.

        .EXAMPLE
            Start-XmipWeb

        .EXAMPLE
            Start-XmipTest -Stress Harsh -PassThru | Start-XmipWeb

        .EXAMPLE
            Start-XmipWeb -Url http://0.0.0.0:5087 -Snapshot .local-work/playground/snapshot.toml
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Xmip.Web')]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [string] $Snapshot,

        [Parameter()]
        [string] $Url = 'http://127.0.0.1:5087',

        [Parameter()]
        [switch] $FromSource,

        [Parameter()]
        [switch] $PassThru
    )

    $layout = Get-XmipPlaygroundLayout
    [string] $source = 'module/operation/gui/src/Xmip.Gui.Web'
    [string] $project = Join-Path -Path $layout.Root -ChildPath $source
    [string[]] $arguments = @("--Kestrel:Endpoints:Http:Url=$Url")

    if (-not [string]::IsNullOrWhiteSpace($Snapshot)) {
        [string] $full = [System.IO.Path]::GetFullPath($Snapshot)
        $arguments += @('--Xmip:Surface=snapshot', "--Xmip:Snapshot=$full")
    }

    [string] $over = if ($arguments.Count -gt 1) { " over $Snapshot" } else { '' }

    if (-not $PSCmdlet.ShouldProcess("the Xmip web monitor at $Url", "Start$over")) {
        return
    }

    if (-not $FromSource -and (Test-Path -LiteralPath $layout.Web)) {
        $launch = @{
            FilePath         = $layout.Web
            ArgumentList     = $arguments
            WorkingDirectory = Split-Path -Parent $layout.Web
            WindowStyle      = 'Hidden'
            PassThru         = $true
        }
    }
    else {
        if (-not (Test-Path -LiteralPath $project)) {
            Write-Error "No web project at $project."
            return
        }

        $launch = @{
            FilePath     = 'dotnet'
            ArgumentList = @('run', '--project', $project, '--no-launch-profile') + $arguments
            PassThru     = $true
        }
    }

    $process = Start-Process @launch
    Write-Verbose "web monitor starting at $Url as pid $($process.Id)"

    if ($PassThru) {
        return ConvertTo-XmipWeb -Process $process
    }
}
