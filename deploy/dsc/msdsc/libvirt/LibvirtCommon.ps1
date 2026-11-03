#requires -PSEdition Core
#requires -Version 7.7.0
# What every Xmip.Libvirt kind shares: virsh against the system connection,
# where the machines of an environment run, and a definition handed to it as
# a file. libvirt's own client, virsh, is the interface: every rule about a
# network, a pool or a domain is libvirt's.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath '../answer/MachineAnswer.ps1')

# The system connection: the one libvirt's virtqemud serves as root, whose
# networks get a bridge and NAT and whose pools any machine reads.
$script:LibvirtConnection = 'qemu:///system'

# KVM's MAC prefix: a machine's static MAC ends in its address's last three
# octets (MachineAnswer.ps1), so the network's DHCP and the kickstart match it.
$script:LibvirtMacPrefix = '525400'

function Invoke-Virsh {
    <#
    .SYNOPSIS
    Runs virsh on the system connection and answers its output; a failure is
    refused with virsh's own words. -Quiet answers $null instead of refusing,
    for a question whose "no" is a failure, such as an unknown name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Argument,

        [Parameter()]
        [switch] $Quiet
    )

    [string[]] $output = @(& virsh --connect $script:LibvirtConnection @Argument 2>&1 |
        ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) {
        if ($Quiet) {
            return $null
        }
        throw "REFUSED: virsh $($Argument -join ' '): $($output -join ' ')"
    }
    return ($output -join "`n")
}

function Invoke-VirshDefinition {
    <#
    .SYNOPSIS
    Hands virsh a definition (net-define, define) as the file it reads.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Command,

        [Parameter(Mandatory = $true)]
        [string] $Definition
    )

    [string] $file = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($file, $Definition, [Text.UTF8Encoding]::new($false))
        Invoke-Virsh -Argument @($Command, $file) | Out-Null
    }
    finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction Ignore
    }
}

function ConvertTo-LibvirtText {
    <#
    .SYNOPSIS
    A value as XML text, for a definition written as a string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Value
    )

    return [Security.SecurityElement]::Escape($Value)
}

function Get-LibvirtMacAddress {
    <#
    .SYNOPSIS
    A machine's static MAC on KVM, colon-separated as libvirt writes it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Address
    )

    [string] $raw = Get-MachineMacAddress -Address $Address -Prefix $script:LibvirtMacPrefix
    return ($raw -replace '(..)(?!$)', '$1:').ToLowerInvariant()
}
