#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipPlaygroundChoice {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [hashtable] $chosen = @{}

    foreach ($name in 'Nodes', 'OnlineNodes', 'Duration', 'TimeFactor', 'LoadBytes') {
        if ($Bound.ContainsKey($name)) { $chosen[$name] = $Bound[$name] }
    }

    return $chosen
}
