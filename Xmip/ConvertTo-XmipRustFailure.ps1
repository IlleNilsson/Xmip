#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What a failed step of the landing's Rust part names: each crate's folder,
    the test and the words that say why.

.DESCRIPTION
    Test-XmipRustChange's failures, read back from what cargo named
    (Get-XmipToolFailure) to the folders the estate names its crates by
    (open problem 146).

    Style: doc/governance/powershell-style.md
#>

function ConvertTo-XmipRustFailure {
    <#
        .SYNOPSIS
            A failed step's failures as Xmip.PartFailure, each crate cargo
            named read back to its folder; the step itself, with the lines
            that say why, where cargo named nothing.

        .PARAMETER Ran
            What Invoke-XmipTool returned.

        .PARAMETER Step
            The step: Name, and Crate, the folder of a step of one crate.

        .PARAMETER Package
            Each member named, its folder to its package.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.PartFailure')]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [pscustomobject] $Ran,

        [Parameter(Mandatory)]
        [pscustomobject] $Step,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Package
    )

    [object[]] $failed = @($Ran.Failure | Where-Object { $null -ne $_ })

    foreach ($one in $failed) {
        [string] $folder = $Step.Crate

        if (-not $folder) {
            [hashtable] $named = @{ Named = $one.Package; Path = $one.Path }
            $folder = Find-XmipFailedCrate -RepositoryRoot $RepositoryRoot -Package $Package @named
        }

        # A crate none of those named, one they build on: named by its package.
        [string] $test = $one.Test

        if (-not $folder -and -not $test) {
            $test = $one.Package
        }

        [string] $said = "$($Step.Name): $($one.Message)"
        New-XmipPartFailure -Module $folder -Test $test -Message $said
    }

    if ($failed.Count -eq 0) {
        [string] $said = "$($Step.Name) failed: $(@($Ran.Telling) -join ' | ')"
        New-XmipPartFailure -Module $Step.Crate -Test $Step.Name -Message $said
    }
}


function Find-XmipFailedCrate {
    <#
        .SYNOPSIS
            The folder of the crate a failure names: by its package, as cargo
            names it or its test program; else by the file a compiler or the
            formatter named, the member holding it; empty where neither says.

        .PARAMETER Named
            The package, or the test program's name with underscores.

        .PARAMETER Path
            The file, absolute or from the root.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Package,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Named = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Path = ''
    )

    foreach ($folder in $Package.Keys) {
        if ($Named -and ($Package[$folder] -replace '_', '-') -eq ($Named -replace '_', '-')) {
            return $folder
        }
    }

    if (-not $Path) {
        return ''
    }

    [string] $file = $Path -replace '^\\\\\?\\', ''

    if ([System.IO.Path]::IsPathRooted($file)) {
        $file = [System.IO.Path]::GetRelativePath($RepositoryRoot, $file)
    }

    $file = $file.Replace('\', '/')
    [string] $holder = @(
        $Package.Keys | Where-Object { $_ -ne '.' -and $file.StartsWith("$_/") } |
            Sort-Object -Property Length -Descending
    ) | Select-Object -First 1

    if ($holder) {
        return $holder
    }

    return @($Package.Keys | Where-Object { $_ -eq '.' }) -join ''
}
