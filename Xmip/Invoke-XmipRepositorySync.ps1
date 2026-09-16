#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Invoke-XmipRepositorySync {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Clone', 'Pull', 'Branch', 'CreateBranch', 'Push', 'Distribute')]
        [string] $Action,

        [Parameter(Mandatory)]
        [hashtable] $Bound
    )

    [hashtable] $argument = @{
        ManifestPath = $Bound.ManifestPath
        Transport = $Bound.Transport
        ModulesOnly = [bool] $Bound.ModulesOnly
        PassThru = [bool] $Bound.PassThru
        WhatIf = $WhatIfPreference
    }

    foreach ($name in 'DestinationPath', 'AllocationPath', 'SourcePath', 'Only') {
        if ($Bound.ContainsKey($name)) { $argument[$name] = $Bound[$name] }
    }

    switch ($Action) {
        'Clone' { $argument.Clone = $true }
        'Pull' { $argument.Pull = $true }
        'Branch' { $argument.Branch = $true }
        'CreateBranch' { $argument.Branch = $true; $argument.Create = $Bound.BranchName }
        'Push' { $argument.Push = $Bound.BranchName }
        'Distribute' { $argument.Distribute = $true }
    }

    return Sync-XmipRepository @argument
}
