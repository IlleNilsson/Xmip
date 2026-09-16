#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Install-XmipEstate {
    <#
        .SYNOPSIS
            Installs the Xmip estate module or its declared prerequisites.

        .EXAMPLE
            Install-XmipEstate -Target Module

        .EXAMPLE
            Install-XmipEstate -Target Prerequisite -Role developer -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Module', 'Prerequisite')]
        [string] $Target = 'Prerequisite',

        [Parameter()]
        [ValidateSet('operator', 'developer', 'build')]
        [string] $Role = 'developer',

        [Parameter()]
        [string] $Path,

        [Parameter()]
        [switch] $IncludeOptional,

        [Parameter()]
        [switch] $Force
    )

    $ErrorActionPreference = 'Stop'

    if ($Target -eq 'Module') {
        return Install-XmipModule -Force:$Force -WhatIf:$WhatIfPreference
    }

    $prerequisite = @{
        Role = $Role
        IncludeOptional = $IncludeOptional
        Install = $true
        WhatIf = $WhatIfPreference
    }

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $prerequisite.ManifestPath = $Path
    }

    Install-XmipPrerequisite @prerequisite
}
