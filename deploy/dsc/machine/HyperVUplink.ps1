# The uplink a gateway machine's second adapter is on, on a Hyper-V host: an
# external switch onto one of the host's adapters, the owner's network
# behind his firewall (deploy/dsc/README.md). It takes a host adapter, so it
# is the owner's to make, once and elevated; a template finds it and never
# makes, changes or removes it. One home for both technologies (ADR-0015,
# amendment 2026-11-24): Microsoft DSC's Xmip.HyperV resources dot-source it
# (deploy/dsc/msdsc/hyperv/HyperVResource.ps1), and Ansible's xmip_machine
# role hands it to the host whole as win_powershell's script
# (tasks/hyperv.yml), so it runs under Windows PowerShell there.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-HyperVUplinkFinding {
    <#
    .SYNOPSIS
    How the uplink differs from one external switch of its name, in words,
    with the command that makes it; nothing when it is one, or where the
    environment names none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Name
    )

    if (-not $Name) {
        return
    }
    [string[]] $types = @(Get-VMSwitch | Where-Object { $_.Name -eq $Name } |
        ForEach-Object { "$($_.SwitchType)" })
    if (($types -join ',') -eq 'External') {
        return
    }
    [string] $found = if ($types.Count -eq 0) { 'absent' } else { $types -join ', ' }
    return ("${Name}: not one external switch ($found), which the gateway machine's " +
        "uplink is on. Made once, elevated: New-VMSwitch -Name '$Name' -NetAdapterName " +
        "<the host's adapter> -AllowManagementOS `$true")
}
