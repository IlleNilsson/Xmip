#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    One line of what Install-XmipPrerequisite found.

.DESCRIPTION
    Style: doc/governance/powershell-style.md
#>


function New-XmipPrerequisiteResult {
    <#
        One line of what Install-XmipPrerequisite found: the prerequisite,
        its status in words, and what was found or what to run.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.Prerequisite')]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Status,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Detail = ''
    )

    return [pscustomobject]@{
        PSTypeName = 'Xmip.Prerequisite'
        name       = $Name
        status     = $Status
        detail     = $Detail
    }
}
