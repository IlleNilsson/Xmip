#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    One file written where its bytes differ, said so: what the estate makes
    or copies from one source, the brand's (Write-XmipBrand) and each
    module's workflow (Write-XmipWorkflow).

    Style: doc/governance/powershell-style.md
#>

function Write-XmipChangedFile {
    # One file written where its bytes differ, said so.
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [byte[]] $Content,

        # What the file is, as the line that says it was written names it.
        [Parameter(Mandatory = $true)]
        [string] $What
    )

    if (Test-Path -LiteralPath $Path) {
        [byte[]] $held = [System.IO.File]::ReadAllBytes($Path)
        if ([System.Linq.Enumerable]::SequenceEqual($held, $Content)) { return }
    }

    if ($PSCmdlet.ShouldProcess($Path, "Write the $($What.ToLowerInvariant())")) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
        [System.IO.File]::WriteAllBytes($Path, $Content)
        Write-XmipStep -Message "${What}: $Path"
    }
}
