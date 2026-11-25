#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Add-XmipDeployGateway {
    <#
        .SYNOPSIS
            The machine the environment's machines reach past the network
            through, where its [environment] names gateway: Gateway, that
            machine's name, address and family, and the uplink its second
            adapter is on; nothing where it names none, the host's own NAT
            then the way out of every machine whose node is online.

        .DESCRIPTION
            The gateway is a Windows machine of the environment, the domain's
            controller in the System Tests' file (the owner, 2026-11-24: "the
            VM DSC can be a gateway to internet for those machines that needs
            it", "A good choice would be the DC"). It translates the network's
            prefix out of a second adapter on the uplink, the switch or bridge
            onto the owner's network, behind his firewall (the same day: "The
            DC would be behind my firewall"), which the host facts found
            (Get-XmipDeployUplink). Each machine whose node declares online is
            given its address as its gateway in place of the host's; the
            gateway machine is given none on the network, its way out the
            uplink's. Every machine's network and the network's own say
            uplink, empty where the machine has no second adapter.

            Refused: gateway naming no Windows machine of the environment.

        .PARAMETER Environment
            The cluster file's [environment].

        .PARAMETER Read
            What Get-XmipDeployEnvironment read: Gateway is added to it.

        .PARAMETER Uplink
            The uplink, the host facts' own; empty where no gateway is named.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment,

        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Uplink = ''
    )

    [string] $named = Get-TomlValue -Node $Environment -Name 'gateway' -Default ''
    $Read['Gateway'] = $null
    $Read.Common.network['uplink'] = ''
    foreach ($machine in $Read.Machines) {
        $machine['network']['uplink'] = ''
    }
    if (-not $named) {
        return
    }
    $gateway = $Read.Machines | Where-Object { $_['name'] -eq "XMIP-$named" } |
        Select-Object -First 1
    if ($null -eq $gateway -or $gateway['image'].family -ne 'Windows') {
        throw "REFUSED: [environment] gateway names $named, no Windows machine of the environment."
    }
    $Read.Common.network['uplink'] = $Uplink
    foreach ($machine in $Read.Machines) {
        if ($machine['name'] -eq $gateway['name']) {
            $machine['network']['gateway'] = ''
            $machine['network']['uplink'] = $Uplink
        }
        elseif ($machine['network']['gateway']) {
            $machine['network']['gateway'] = $gateway['address']
        }
    }
    $Read['Gateway'] = @{
        machine = @{ name = $gateway['name']; address = $gateway['address']; family = 'Windows' }
        uplink = $Uplink
    }
}
