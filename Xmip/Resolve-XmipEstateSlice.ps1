#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Resolve-XmipEstateSlice {
    <# Returns the requested repositories and their complete dependency closure. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Manifest,

        [Parameter(Mandatory)]
        [string[]] $Include
    )

    [hashtable] $byName = @{}

    foreach ($repository in @($Manifest.repositories)) {
        $byName[[string] $repository.name] = $repository
    }

    [Collections.Generic.HashSet[string]] $resolved = [Collections.Generic.HashSet[string]]::new()
    [Collections.Generic.Queue[string]] $pending = [Collections.Generic.Queue[string]]::new()

    foreach ($requested in $Include) { $pending.Enqueue($requested) }

    while ($pending.Count -gt 0) {
        [string] $name = $pending.Dequeue()

        if (-not $byName.ContainsKey($name)) {
            throw "The manifest declares no repository '$name'."
        }
        if (-not $resolved.Add($name)) { continue }

        foreach ($dependency in @($byName[$name].dependencies)) {
            $pending.Enqueue([string] $dependency)
        }
    }

    return @($resolved | Sort-Object)
}
