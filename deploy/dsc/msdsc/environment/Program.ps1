#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The one way the resources of this folder run a program: on the node, its
    package's tools and xmip-service; on the machine deploying the
    environment, xmip-service slicing each node's configuration.

    Style: doc/governance/powershell-style.md
#>

function Invoke-DscProgram {
    <#
    .SYNOPSIS
    Run a program and answer its standard output's lines; a failure throws
    with what it said.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Program,

        [Parameter()]
        [string[]] $Argument = @()
    )

    [string[]] $said = @(& $Program @Argument 2>&1 | ForEach-Object { "$_" })

    if ($LASTEXITCODE -ne 0) {
        throw "$Program $($Argument -join ' ') exited $LASTEXITCODE`: $($said -join ' ')"
    }

    return $said
}
