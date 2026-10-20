#requires -PSEdition Core
#requires -Version 7.6.7

<#
.SYNOPSIS
    Whether a module's tests load the runtime's library.

.DESCRIPTION
    Apart from Test-XmipChangeTree.ps1 since 2026-10-13, when the landing's
    progress line would have taken that file past the 400 lines the estate
    allows a file.

    Style: doc/governance/powershell-style.md
#>


function Test-XmipRuntimeLibraryReader {
    <#
        .SYNOPSIS
            Whether a Rust module's sources, or the scripts at its root that
            the landing runs (its Event bindings' verification), read
            XMIP_RUNTIME_LIBRARY, the variable naming the runtime library its
            tests load.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    [System.IO.FileInfo[]] $sources = @(
        foreach ($folder in @('.src', 'src')) {
            [string] $at = Join-Path -Path $Path -ChildPath $folder
            if (Test-Path -LiteralPath $at) {
                Get-ChildItem -LiteralPath $at -Recurse -Filter '*.rs' -File
            }
        }
        Get-ChildItem -LiteralPath $Path -Filter '*.ps1' -File
    )

    if ($sources.Count -eq 0) {
        return $false
    }

    [hashtable] $search = @{
        LiteralPath = $sources.FullName
        Pattern     = 'XMIP_RUNTIME_LIBRARY'
        SimpleMatch = $true
        Quiet       = $true
    }

    [bool] (Select-String @search)
}
