#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Build-XmipOperationWeb {
    <#
        .SYNOPSIS
            Builds the web host before it is started, so it runs the source as
            it is.

        .DESCRIPTION
            Start-XmipOperationWeb builds the host as Start-XmipTest builds a
            roll. Until 2026-09-29 it ran whatever bin held, and xgit builds
            elsewhere, so a fix landed the day before was not what the owner
            saw. A project that is not there, or one that does not build, is
            refused in words.

        .PARAMETER Root
            The estate's root, which holds the web host's project.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Root
    )

    [string] $source = 'module/core/operation/gui/src/Xmip.Gui.Web'
    [string] $project = Join-Path -Path $Root -ChildPath $source

    if (-not (Test-Path -LiteralPath $project)) {
        throw "No web project at $project."
    }

    [string[]] $building = @('build', $project, '--verbosity', 'quiet', '--nologo')
    [pscustomobject] $built = Invoke-XmipTool -Tool dotnet -Argument $building -Output Keep

    if (-not $built.Passed) {
        throw "REFUSED. The web host did not build:`n$($built.Said -join "`n")"
    }
}
