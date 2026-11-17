#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The configuration Xmip runs — a cluster's cluster.xmip, a node's own
    document — read and written by the runtime's one reader.

.DESCRIPTION
    What the runtime reads is what the tooling reads: xmip-core-configure,
    through the operator module, Xmip.Surface over the C ABI (xmip_operate.h
    section 27; ADR-0031, amendment 2026-11-17). Until that day the module
    read a cluster's file with PSToml, a second parser. The estate's own
    manifests and records stay on Read-XmipToml: the tool that builds the
    runtime reads those, and cannot need it (open problem 25, row u).

    Style: doc/governance/powershell-style.md
#>


function Read-XmipConfiguration {
    <#
        .SYNOPSIS
            A configuration Xmip runs, read by the runtime's one reader: its
            tables as dictionaries, an array as an array, a date or time as
            its TOML text. Read with Get-TomlKey and Get-TomlValue, as every
            document the module reads is.

        .DESCRIPTION
            Throws REFUSED, in the reader's words, where the file is not TOML.

        .PARAMETER Path
            The file.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [string] $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop
    Import-XmipOperatorModule
    [string] $answer = ''

    if (-not [Xmip.Surface.RuntimeLibrary]::Rules.Documents.TryRead($text, [ref] $answer)) {
        throw "REFUSED. ${Path}: $answer"
    }

    return (ConvertFrom-Json -InputObject $answer -AsHashtable)
}


function Write-XmipConfiguration {
    <#
        .SYNOPSIS
            Writes a configuration Xmip runs as the runtime's writer writes
            it, whole (Write-XmipWholeFile), each of -Comment a line above it.

        .PARAMETER Path
            The file.

        .PARAMETER Value
            The document: a table a dictionary, a value a string, a number or
            a boolean, an array an array. Nothing in it is null.

        .PARAMETER Comment
            Lines said above the document, each written as a TOML comment.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Value,

        [Parameter(Mandatory = $false)]
        [string[]] $Comment = @()
    )

    Import-XmipOperatorModule
    [string] $json = ConvertTo-Json -InputObject $Value -Depth 32 -Compress
    [string] $text = ''

    if (-not [Xmip.Surface.RuntimeLibrary]::Rules.Documents.TryWrite($json, [ref] $text)) {
        throw "REFUSED. ${Path}: $text"
    }

    [string[]] $said = @($Comment | ForEach-Object { "# $_`n" })

    if ($PSCmdlet.ShouldProcess($Path, 'Write the configuration')) {
        Write-XmipWholeFile -Path $Path -Text (($said -join '') + $text)
    }
}
