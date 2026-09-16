#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipTestResultView {
    [CmdletBinding()]
    [OutputType('Xmip.TestResult')]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [hashtable] $argument = @{ Worst = [bool] $Bound.Worst }

    foreach ($name in 'Path', 'Test', 'Node') {
        if ($Bound.ContainsKey($name)) { $argument[$name] = $Bound[$name] }
    }

    return Get-XmipTestResult @argument
}
