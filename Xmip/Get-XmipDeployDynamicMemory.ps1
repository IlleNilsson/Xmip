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
            most; any other is refused in words before anything is made. On
            libvirt a guest is given its memory back from a virtio balloon,
            and Windows has no balloon driver of its own, so a Windows
            machine there is refused it: its memory is static.

        .PARAMETER Machine
            One [[machines]] table of the environment file.

        .PARAMETER Hypervisor
            The environment's hypervisor, libvirt or hyperv.

        .PARAMETER Family
            The machine's system, its image's family: Windows or Linux.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Machine,

        [Parameter(Mandatory)]
        [string] $Hypervisor,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Family
    )

    $dynamic = Get-TomlValue -Node $Machine -Name 'dynamic_memory' -Default $null
    if ($null -eq $dynamic) {
        return @{}
    }
    [string] $name = Get-TomlValue -Node $Machine -Name 'name'
    if ($Hypervisor -eq 'libvirt' -and $Family -eq 'Windows') {
        throw ("REFUSED: $name runs Windows on libvirt, whose dynamic memory is a virtio " +
            'balloon, and Windows has no balloon driver of its own: leave its ' +
            'dynamic_memory out, and its memory_gb is static (deploy/dsc/README.md).')
    }
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
