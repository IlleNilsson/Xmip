#requires -PSEdition Core
#requires -Version 7.7.0
# The Xmip.HyperV/Network kind (HyperVResource.ps1): the network an
# environment's machines share on one Hyper-V host. An internal virtual
# switch; the host's address on the switch's adapter, "vEthernet (<switch>)",
# the machines' gateway and that adapter's one manual IPv4 address; and
# outbound NAT for the network's prefix, named for the environment, or none
# where the environment turns it off.
#
# What is not there yet is found absent, never refused: each question lists
# what the host has and looks for the instance in it, so only the host's own
# refusal, Hyper-V's permission for one, is an error.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-HyperVSwitch {
    <#
    .SYNOPSIS
    The virtual switches of the name; nothing where there is none.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    return (Get-VMSwitch | Where-Object { $_.Name -eq $Name })
}

function Get-HyperVSwitchFinding {
    <#
    .SYNOPSIS
    How the switch differs from an internal one of the name, in words:
    absent, or not internal; nothing when it is one.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    [object[]] $switches = @(Get-HyperVSwitch -Name $Name)
    if ($switches.Count -eq 0) {
        return "${Name}: absent."
    }
    [string[]] $types = @($switches | ForEach-Object { "$($_.SwitchType)" })
    if (($types -join ',') -ne 'Internal') {
        return "${Name}: not one internal switch ($($types -join ', '))."
    }
    return $null
}

function Get-HyperVHostAddress {
    <#
    .SYNOPSIS
    The manual IPv4 addresses of the host's adapter on the switch, each its
    Text, address/prefix length, and its Entry, the address itself; nothing
    where the switch or its adapter is not there.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Switch
    )

    [string] $alias = "vEthernet ($Switch)"
    return (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.InterfaceAlias -eq $alias -and "$($_.PrefixOrigin)" -eq 'Manual'
    } | ForEach-Object {
        [pscustomobject] @{ Text = "$($_.IPAddress)/$($_.PrefixLength)"; Entry = $_ }
    })
}

function Get-HyperVNatFinding {
    <#
    .SYNOPSIS
    How the environment's NAT differs from its instance, in words: absent or
    for another prefix where it is on, present where it is off.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['environment']
    [string] $prefix = $Instance['prefix']
    [object[]] $nat = @(Get-NetNat | Where-Object { $_.Name -eq $name })
    if (-not $Instance['nat']) {
        if ($nat.Count -gt 0) {
            return "${name}: NAT is there; the environment turns it off."
        }
        return $null
    }
    if ($nat.Count -eq 0) {
        return "${name}: NAT for $prefix absent."
    }
    [string[]] $found = @($nat | ForEach-Object { $_.InternalIPInterfaceAddressPrefix })
    if (($found -join ',') -ne $prefix) {
        return "${name}: NAT for $($found -join ', '), not $prefix."
    }
    return $null
}

function Get-HyperVNetworkFinding {
    <#
    .SYNOPSIS
    How the network differs from its instance, in words; nothing when it
    does not.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [string] $gateway = "$($Instance['gateway'])/$($Instance['prefixLength'])"
    [string[]] $held = @(Get-HyperVHostAddress -Switch $name | ForEach-Object { $_.Text })
    [string[]] $finding = @(
        Get-HyperVSwitchFinding -Name $name
        if (($held -join ',') -ne $gateway) {
            "${name}: the host's address on it is not $gateway alone."
        }
        Get-HyperVNatFinding -Instance $Instance
    )
    return @($finding | Where-Object { -not [string]::IsNullOrEmpty($_) })
}

function Get-HyperVNetworkState {
    <#
    .SYNOPSIS
    Whether the network's switch exists (_exist), and how the network
    differs from its instance (findings).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [object[]] $findings = @(Get-HyperVNetworkFinding -Instance $Instance)
    return @{
        _exist = @(Get-HyperVSwitch -Name $Instance['name']).Count -gt 0
        findings = $findings
    }
}

function Set-HyperVNetwork {
    <#
    .SYNOPSIS
    Makes the internal switch where it is absent, gives the host its address
    on it and the NAT the environment says. A switch of the name that is
    not one internal switch is refused, never changed: machines may be on it.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [string] $switch = Get-HyperVSwitchFinding -Name $name
    [bool] $absent = $switch -eq "${name}: absent."
    if (-not $absent -and -not [string]::IsNullOrEmpty($switch)) {
        throw "REFUSED: $switch It is not changed."
    }
    if (-not $PSCmdlet.ShouldProcess($name, 'Make the switch, the host address and NAT')) {
        return
    }
    if ($absent) {
        New-VMSwitch -Name $name -SwitchType Internal | Out-Null
    }
    Set-HyperVHostAddress -Instance $Instance
    Set-HyperVNat -Instance $Instance
}

function Set-HyperVHostAddress {
    <#
    .SYNOPSIS
    Leaves the gateway, with its prefix length, the one manual IPv4 address
    of the host's adapter on the switch.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['name']
    [string] $gateway = "$($Instance['gateway'])/$($Instance['prefixLength'])"
    [object[]] $held = @(Get-HyperVHostAddress -Switch $name)
    if (-not $PSCmdlet.ShouldProcess("vEthernet ($name)", "Hold $gateway alone")) {
        return
    }
    foreach ($address in @($held | Where-Object { $_.Text -ne $gateway })) {
        $address.Entry | Remove-NetIPAddress -Confirm:$false
    }
    if (@($held | Where-Object { $_.Text -eq $gateway }).Count -eq 0) {
        [hashtable] $address = @{
            InterfaceAlias = "vEthernet ($name)"
            IPAddress = $Instance['gateway']
            PrefixLength = $Instance['prefixLength']
        }
        New-NetIPAddress @address | Out-Null
    }
}

function Set-HyperVNat {
    <#
    .SYNOPSIS
    Gives the network's prefix NAT, named for the environment, where the
    environment turns it on, and removes it where it turns it off.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $name = $Instance['environment']
    if ([string]::IsNullOrEmpty((Get-HyperVNatFinding -Instance $Instance)) -or
        -not $PSCmdlet.ShouldProcess($name, 'Make NAT as the environment says')) {
        return
    }
    if (@(Get-NetNat | Where-Object { $_.Name -eq $name }).Count -gt 0) {
        Remove-NetNat -Name $name -Confirm:$false
    }
    if ($Instance['nat']) {
        New-NetNat -Name $name -InternalIPInterfaceAddressPrefix $Instance['prefix'] | Out-Null
    }
}
