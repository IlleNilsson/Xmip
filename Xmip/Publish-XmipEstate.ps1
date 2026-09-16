#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Publish-XmipEstate {
    <#
        .SYNOPSIS
            Tests, commits and publishes changes across the Xmip estate.

        .EXAMPLE
            Publish-XmipEstate -Message 'Conform the PowerShell surfaces' -WhatIf

        .EXAMPLE
            Publish-XmipEstate -Pin
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [Alias('m')]
        [string] $Message = 'Pin the estate',

        [Parameter()]
        [switch] $All,

        [Parameter()]
        [switch] $NoVerify,

        [Parameter()]
        [switch] $Pin,

        [Parameter()]
        [string] $Path = (Get-XmipRepositoryRoot)
    )

    $parameters = @{
        Message = $Message
        All = $All
        NoVerify = $NoVerify
        Pin = $Pin
        RepositoryRoot = $Path
        WhatIf = $WhatIfPreference
    }

    return Publish-XmipChange @parameters
}
