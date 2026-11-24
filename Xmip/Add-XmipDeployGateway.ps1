#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Add-XmipDeployGateway {
    <#
        .SYNOPSIS
            The machine the environment's machines reach past the network
            through, where its network names gateway_machine: Gateway, that
            machine's name, address and family, and the uplink its second
            adapter is on; nothing where it names none, the host's own NAT,
            nat, the way out as before.

        .DESCRIPTION
            The gateway machine is a Windows machine of the environment, the
            domain's controller in the examples (the owner, 2026-11-24: "the
            VM DSC can be a gateway to internet for those machines that needs
            it", "A good choice would be the DC"). It translates the
            network's prefix out of a second adapter on uplink, the switch or
            bridge onto the owner's network, behind his firewall (the same
            day: "The DC would be behind my firewall"). Each machine whose
            internet says so is given its address as its gateway in place of
            the host's; the gateway machine is given none on the network, its
            way out the uplink's, and the uplink its second adapter is on.
            Every machine's network and the network's own say uplink, empty
            where the machine has no second adapter.

            Refused: gateway_machine naming no Windows machine of the
            environment, a gateway machine with no uplink, and one beside the
            host's NAT, since the network has one way out.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment,

        [Parameter(Mandatory)]
        [hashtable] $Read
    )

    $network = Get-TomlValue -Node $Environment -Name 'network'
    [string] $named = Get-TomlValue -Node $network -Name 'gateway_machine' -Default ''
    [string] $uplink = Get-TomlValue -Node $network -Name 'uplink' -Default ''
    $Read['Gateway'] = $null
    $Read.Common.network['uplink'] = ''
    foreach ($machine in $Read.Machines) {
        $machine['network']['uplink'] = ''
    }
    if (-not $named) {
        return
    }
    $gateway = $Read.Machines | Where-Object { $_['name'] -eq $named } | Select-Object -First 1
    if ($null -eq $gateway -or $gateway['image'].family -ne 'Windows') {
        throw "REFUSED: gateway_machine names $named, no Windows machine of the environment."
    }
    if (-not $uplink) {
        throw ("REFUSED: gateway_machine $named reaches past the network through [network] " +
            'uplink, the switch (Hyper-V: an external one) or bridge (libvirt) its second ' +
            'adapter is on: write it in your copy of the environment file.')
    }
    if ($Read.Common.network.enableNat) {
        throw ("REFUSED: the network names gateway_machine $named and nat, two ways out: " +
            'nat = false, or no gateway_machine.')
    }
    $Read.Common.network['uplink'] = $uplink
    foreach ($machine in $Read.Machines) {
        if ($machine['name'] -eq $named) {
            $machine['network']['gateway'] = ''
            $machine['network']['uplink'] = $uplink
        }
        elseif ($machine['network']['gateway']) {
            $machine['network']['gateway'] = $gateway['address']
        }
    }
    $Read['Gateway'] = @{
        machine = @{ name = $named; address = $gateway['address']; family = 'Windows' }
        uplink = $uplink
    }
}
