#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipTestHistoryView {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [hashtable] $argument = @{}

    foreach ($name in 'Path', 'Counted', 'Since') {
        if ($Bound.ContainsKey($name)) { $argument[$name] = $Bound[$name] }
    }

    return Get-XmipHistory @argument
}
