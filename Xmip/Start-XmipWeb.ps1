#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Start-XmipWeb {
    <#
        .SYNOPSIS
            Starts the Xmip web monitoring UI and returns its address.

        .DESCRIPTION
            The web surface is monitoring only (ADR-0014): it reads the operator
            boundary — or, while there is no running node, the Playground's
            snapshot — and shows the cluster, drill-down and history. This starts
            it detached and hands back the URL, so an operator does not have to
            remember the dotnet invocation or the Kestrel override.

            It launches the built executable when one is present and falls back
            to `dotnet run` from source otherwise. It binds to 127.0.0.1 by
            default rather than localhost, because a browser that cached HSTS for
            localhost from another app silently forces https and the plain-http
            server then looks dead.

        .PARAMETER Url
            Where to bind. Defaults to http://127.0.0.1:5087. Use
            http://0.0.0.0:5087 to reach it from another device on the network
            (the firewall must also allow the port).

        .PARAMETER FromSource
            Run `dotnet run` from the project rather than the built executable —
            for development, when the source is newer than the last build.

        .EXAMPLE
            Start-XmipWeb

        .EXAMPLE
            Start-XmipWeb -Url http://0.0.0.0:5087
    #>
    [CmdletBinding()]
    [OutputType([System.Diagnostics.Process])]
    param(
        [Parameter()]
        [string] $Url = 'http://127.0.0.1:5087',

        [Parameter()]
        [switch] $FromSource
    )

    [string] $root = Get-XmipRepositoryRoot
    [string] $project = Join-Path $root 'modules/operations/gui/src/Xmip.Gui.Web'
    [string] $exe = Join-Path $project 'bin/Debug/net11.0/Xmip.Gui.Web.exe'
    [string] $kestrel = "--Kestrel:Endpoints:Http:Url=$Url"

    if (-not $FromSource -and (Test-Path -LiteralPath $exe)) {
        $launch = @{
            FilePath         = $exe
            ArgumentList     = $kestrel
            WorkingDirectory = Split-Path -Parent $exe
            PassThru         = $true
        }
        $process = Start-Process @launch
    }
    else {
        if (-not (Test-Path -LiteralPath $project)) {
            Write-Error "No web project at $project."
            return
        }

        [string[]] $arguments = @(
            'run', '--project', $project, '--no-launch-profile', $kestrel
        )
        $process = Start-Process -FilePath 'dotnet' -ArgumentList $arguments -PassThru
    }

    Write-Host "Xmip web monitor starting at $Url (pid $($process.Id))" -ForegroundColor Green
    Write-Host 'Stop it with: Stop-Process -Id' $process.Id

    $process
}
