#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    A file written whole: the module's one way to put text where a reader
    may be polling for it.

.DESCRIPTION
    Write-XmipToml, the tooling's TOML, and Write-XmipConfiguration, the
    configuration Xmip runs, both write through it.

    Style: doc/governance/powershell-style.md
#>


function Write-XmipWholeFile {
    <#
        .SYNOPSIS
            Writes text to a file whole. -NoClobber refuses a file that is
            already there, and the refusal is an error the caller can catch.

        .DESCRIPTION
            The text is written beside the file and only then moved into
            place, so a reader finds the file whole or not at all: written in
            place, a reader polling for it read it empty for the instant
            between its creation and its text (the estate suite's own test,
            2026-10-22). A move over a file a reader holds open for that
            instant is asked again.

        .PARAMETER Path
            The file.

        .PARAMETER Text
            What it holds, written as UTF-8.

        .PARAMETER NoClobber
            Refuse a file that is already there.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory = $false)]
        [switch] $NoClobber
    )

    [string] $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
    [string] $beside = "$full.$([System.Guid]::NewGuid().ToString('n')).new"

    [hashtable] $written = @{
        InputObject = $Text
        LiteralPath = $beside
        Encoding    = 'utf8'
        ErrorAction = 'Stop'
    }

    Out-File @written

    try {
        if ($NoClobber.IsPresent) {
            [System.IO.File]::Move($beside, $full, $false)
            return
        }

        for ([int] $attempt = 1; ; $attempt++) {
            try {
                [System.IO.File]::Move($beside, $full, $true)
                return
            }
            catch [System.IO.IOException] {
                if ($attempt -ge 1000) {
                    throw
                }

                [System.Threading.Thread]::Sleep(1)
            }
        }
    }
    catch {
        Remove-Item -LiteralPath $beside -Force -ErrorAction SilentlyContinue
        throw
    }
}
