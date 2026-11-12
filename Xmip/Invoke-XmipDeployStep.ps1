#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Invoke-XmipDeployStep {
    <#
        One document applied or tested by dsc, with the values of the
        parameters it declares, a parameter with a default value of its own
        left to it where the step gives none; answers whether every resource
        is in its desired state. What dsc says goes to the log; a failure is
        refused with dsc's own last errors.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Step,

        [Parameter(Mandatory)]
        [ValidateSet('set', 'test')]
        [string] $Operation,

        [Parameter(Mandatory)]
        [string] $Log
    )

    [System.Collections.IDictionary] $wanted = (Read-XmipYaml -Path $Step.Document)['parameters']
    [hashtable] $value = @{}
    foreach ($name in $wanted.Keys) {
        if ($Step.Value.ContainsKey($name)) {
            $value[$name] = $Step.Value[$name]
        }
    }
    [string] $parameters = Join-Path $Log "$($Step.Name).parameters.yaml"
    Write-XmipYaml -Path $parameters -Value @{ parameters = $value }
    [string] $trace = Join-Path $Log 'run.log'
    [datetime] $begun = [datetime]::UtcNow
    "== $($begun.ToString('o')) $Operation $($Step.Name)" | Add-Content -LiteralPath $trace
    # The template's own resources are found on PATH, beside its documents.
    [string] $path = $env:PATH
    $env:PATH = (Split-Path -Path $Step.Document -Parent) + [IO.Path]::PathSeparator + $path
    try {
        [string[]] $arguments = @('config', '--parameters-file', $parameters, $Operation,
            '--file', $Step.Document)
        [string] $json = (& dsc @arguments 2>> $trace) -join "`n"
        [int] $exit = $LASTEXITCODE
        if ($exit -eq 0 -and $Operation -eq 'set') {
            $arguments[3] = 'test'
            $json = (& dsc @arguments 2>> $trace) -join "`n"
            $exit = $LASTEXITCODE
        }
    }
    finally {
        $env:PATH = $path
    }
    $json | Add-Content -LiteralPath $trace
    [int] $seconds = ([datetime]::UtcNow - $begun).TotalSeconds
    [string[]] $errors = @(Get-Content -LiteralPath $trace -Tail 200 |
        Where-Object { $_ -match 'ERROR' } | Select-Object -Last 3)
    # Every template's resources answer what is not there yet as absent, so a
    # dsc that fails is refused, tested or set.
    if ($exit -ne 0) {
        throw "REFUSED: $($Step.Name): dsc $Operation exit $exit. $($errors -join ' ') ($trace)"
    }
    [object[]] $results = @(($json | ConvertFrom-Json -AsHashtable)['results'])
    [object[]] $differ = @($results | Where-Object { -not $_['result']['inDesiredState'] })
    return @{
        Step = $Step.Name
        InDesiredState = $differ.Count -eq 0
        Seconds = $seconds
    }
}

function Write-XmipDeployLine {
    <#
        One line per step: the departure, expected and actual, and the
        estimated arrival, clock times; the time elapsed, left and in all;
        then which step and how it stands. -Index -1 is a round of waiting
        for an installation, whose end is not known.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Step,

        [Parameter(Mandatory)]
        [hashtable] $Result,

        [Parameter(Mandatory)]
        [int] $Index,

        [Parameter(Mandatory)]
        [int] $Count,

        [Parameter(Mandatory)]
        [datetime] $Started
    )

    [datetime] $now = [datetime]::UtcNow
    [timespan] $elapsed = $now - $Started
    [string] $state = if ($Result.InDesiredState) { 'in its desired state' }
    else { 'not yet in its desired state' }
    # The departure, expected and actual, is the command's start; the arrival
    # is estimated at the pace so far. A round of waiting has no estimate.
    [string] $departure = $Started.ToLocalTime().ToString('HH:mm')
    [string] $left = 'unknown'
    [string] $total = 'unknown'
    [string] $eta = 'unknown'
    if ($Index -ge 0) {
        [timespan] $remaining = [timespan]::FromSeconds(
            $elapsed.TotalSeconds / ($Index + 1) * ($Count - $Index - 1))
        $left = $remaining.ToString('h\:mm\:ss')
        $total = ($elapsed + $remaining).ToString('h\:mm\:ss')
        $eta = $now.Add($remaining).ToLocalTime().ToString('HH:mm')
    }
    [string] $place = if ($Index -ge 0) { "step $($Index + 1) of $Count" } else { 'waiting' }
    # A middle dot between the fields, written by its code point.
    [string] $dot = " $([char] 0x00B7) "
    [string] $times = @(
        "ETD: $departure", "ATD: $departure", "ETA: $eta"
        "Elapsed: $($elapsed.ToString('h\:mm\:ss'))", "Left: $left", "Total: $total"
    ) -join $dot
    Write-Host -Object "$times$dot${place}: $($Step.Name) $state ($($Result.Seconds) s)"
}
