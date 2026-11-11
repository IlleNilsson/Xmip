#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The starts of a program the demo readiness check makes: the Desktop
    operations app (Test-XmipDemoDesktop.ps1) and a language server
    (Test-XmipDemoExtension.ps1).

.DESCRIPTION
    A module file starts a process only behind a Start-* door (the owner,
    2026-09-12: nothing starts itself), and these are the check's. Each is
    audited as it starts, with its pid, as Start-XmipOperationWeb audits the
    web host it starts (ADR-0062), so a run that is killed mid-part still
    leaves a record of what it started. Each is started by a person's
    Start-XmipTest -Suite Core.Demo alone; the check's stop part, or
    Stop-XmipTest, ends the desktop app, and the extension part ends the
    language server (ADR-0028, amendment 2026-11-10).

    Style: doc/governance/powershell-style.md
#>


function Start-XmipDemoDesktop {
    <#
        .SYNOPSIS
            Starts the Desktop operations app the check built, in its own
            folder, where it reads the gui.toml deployed beside it, and
            returns the process at once.

        .PARAMETER Program
            The app's executable.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Diagnostics.Process])]
    param(
        [Parameter(Mandatory)]
        [string] $Program
    )

    if (-not $PSCmdlet.ShouldProcess($Program, 'Start the Desktop operations app')) {
        return
    }

    [string] $folder = Split-Path -Path $Program -Parent
    Initialize-XmipAudit
    $process = Start-Process -FilePath $Program -WorkingDirectory $folder -PassThru
    Write-XmipAudit -Action 'Start-XmipDemoDesktop' -Phase Begin -Property @{
        Id       = $process.Id
        Program  = $Program
        Document = Join-Path -Path $folder -ChildPath 'gui.toml'
    }

    return $process
}


function Start-XmipLanguageServer {
    <#
        .SYNOPSIS
            Starts a language server as an editor starts it, over stdio — its
            standard input and output redirected, no window — and returns
            the process at once. Whoever starts it ends it.

        .PARAMETER Path
            The server's executable.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.Diagnostics.Process])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Start the language server over stdio')) {
        return
    }

    $start = [System.Diagnostics.ProcessStartInfo]::new($Path)
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.CreateNoWindow = $true
    Initialize-XmipAudit
    $server = [System.Diagnostics.Process]::Start($start)
    Write-XmipAudit -Action 'Start-XmipLanguageServer' -Phase Begin -Property @{
        Id      = $server.Id
        Program = $Path
    }

    return $server
}
