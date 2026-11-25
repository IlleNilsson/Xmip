#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Add-XmipDeployDomain {
    <#
        .SYNOPSIS
            The environment's Active Directory domain, where its [environment]
            names domain_controller: Domain, the domain with its controller and
            every other Windows machine, its members, each a name, address
            and family; nothing where it names none.

        .DESCRIPTION
            The controller is a Windows machine of the environment and the
            network's DNS server, its address the network's dns_server, since
            every member finds the domain through it; a name that is no
            Windows machine of the environment is refused.

        .PARAMETER Environment
            The cluster file's [environment].

        .PARAMETER Read
            What Get-XmipDeployEnvironment read: Domain is added to it.
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
    [hashtable[]] $windows = @($Read.Listed | Where-Object { $_.family -eq 'Windows' } |
            ForEach-Object { @{ name = $_.machine; address = $_.address; family = 'Windows' } })
    $controller = $windows | Where-Object { $_.name -eq "XMIP-$named" } | Select-Object -First 1
    if ($null -eq $controller) {
        throw ("REFUSED: [environment] domain_controller names $named, no Windows machine " +
            'of the environment.')
    }
    $Read['Domain'] = @{
        name = $Read.Common.domainName
        controller = $controller
        members = @($windows | Where-Object { $_.name -ne $controller.name })
    }
}
