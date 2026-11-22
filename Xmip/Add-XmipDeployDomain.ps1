#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Add-XmipDeployDomain {
    <#
        .SYNOPSIS
            The environment's Active Directory domain, where its file names
            domain_controller: Domain, the domain with its controller and
            every other Windows machine, its members, each a name, address
            and family; nothing where it names none.

        .DESCRIPTION
            The controller is a Windows machine of the environment and the
            network's DNS server, since every member finds the domain
            through it; anything else is refused.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment,

        [Parameter(Mandatory)]
        [hashtable] $Read
    )

    [string] $named = Get-TomlValue -Node $Environment -Name 'domain_controller' -Default ''
    $Read['Domain'] = $null
    if (-not $named) {
        return
    }
    [hashtable[]] $windows = @($Read.Machines | Where-Object { $_['image'].family -eq 'Windows' } |
            ForEach-Object { @{ name = $_['name']; address = $_['address']; family = 'Windows' } })
    $controller = $windows | Where-Object { $_.name -eq $named } | Select-Object -First 1
    if ($null -eq $controller) {
        throw "REFUSED: domain_controller names $named, no Windows machine of the environment."
    }
    if ($controller.address -ne $Read.Common.network.dnsServer) {
        throw ("REFUSED: domain_controller $named is at $($controller.address), and the " +
            "network's dns_server is $($Read.Common.network.dnsServer): its members find the " +
            'domain through its DNS server.')
    }
    $Read['Domain'] = @{
        name = $Read.Common.domainName
        controller = $controller
        members = @($windows | Where-Object { $_.name -ne $named })
    }
}
