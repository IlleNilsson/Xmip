#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipDeployDynamicMemory {
    <#
        .SYNOPSIS
            A machine's dynamic memory as its environment file says it, in
            MiB: the least and the most its hypervisor may give it, its
            memory_gb the memory it starts with; none, an empty table, where
            it says none, and the machine's memory is static.

        .DESCRIPTION
            dynamic_memory = { minimum_gb = 0.5, maximum_gb = 3 } on a
            machine (deploy/dsc/README.md). Hyper-V takes each in steps of
            2 MiB, and the least at most the start and the start at most the
            most; any other is refused in words before anything is made.

        .PARAMETER Machine
            One [[machines]] table of the environment file.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Machine
    )

    $dynamic = Get-TomlValue -Node $Machine -Name 'dynamic_memory' -Default $null
    if ($null -eq $dynamic) {
        return @{}
    }
    [string] $name = Get-TomlValue -Node $Machine -Name 'name'
    [hashtable] $mib = @{ startup = [double] (Get-TomlValue -Node $Machine -Name 'memory_gb') }
    foreach ($key in 'minimum', 'maximum') {
        $mib[$key] = [double] (Get-TomlValue -Node $dynamic -Name "${key}_gb")
    }
    foreach ($key in @($mib.Keys)) {
        [double] $exact = $mib[$key] * 1024
        if ($exact -ne [math]::Floor($exact) -or $exact % 2 -ne 0 -or $exact -le 0) {
            throw ("REFUSED: $name's $key memory, $($mib[$key]) GB, is not a whole number " +
                'of 2 MiB steps, as Hyper-V takes it.')
        }
        $mib[$key] = [long] $exact
    }
    if ($mib.minimum -gt $mib.startup -or $mib.startup -gt $mib.maximum) {
        throw ("REFUSED: $name's dynamic memory is minimum_gb <= memory_gb <= maximum_gb; " +
            "it says $($mib.minimum) MiB, $($mib.startup) MiB and $($mib.maximum) MiB.")
    }
    return @{ minimumMB = $mib.minimum; maximumMB = $mib.maximum }
}
