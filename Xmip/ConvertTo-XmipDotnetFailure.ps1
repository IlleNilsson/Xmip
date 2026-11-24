#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What a failed build or test of a .NET project names: the module, the
    project and each test, and the words that say why.

.DESCRIPTION
    Test-XmipDotnetModule's failures, read from what dotnet said
    (Get-XmipToolFailure) (open problem 146).

    Style: doc/governance/powershell-style.md
#>


function ConvertTo-XmipDotnetFailure {
    <#
        .SYNOPSIS
            A failed dotnet build or test as Xmip.PartFailure: the module, and
            the project with each test or error dotnet named; the project
            with the lines that say why, where it named none.

        .PARAMETER Ran
            What Invoke-XmipTool returned.

        .PARAMETER Name
            The module's folder.

        .PARAMETER Project
            The project built or tested, by its name.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.PartFailure')]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Ran,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Project
    )

    [object[]] $failed = @($Ran.Failure | Where-Object { $null -ne $_ })

    foreach ($one in $failed) {
        [string] $test = if ($one.Test) { "$Project $($one.Test)" } else { $Project }
        New-XmipPartFailure -Module $Name -Test $test -Message $one.Message
    }

    if ($failed.Count -eq 0) {
        New-XmipPartFailure -Module $Name -Test $Project -Message (
            "failed: $(@($Ran.Telling) -join ' | ')")
    }
}
