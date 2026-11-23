#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Add-XmipDeployFarEnd {
    <#
        .SYNOPSIS
            The Systems Tests' far ends an environment runs on machines of their
            own, added to what Get-XmipDeployEnvironment read: each machine's
            external, the far end it runs, with the machine; and, where any
            does, the program each family runs them by and the folder of
            their certificates.

        .DESCRIPTION
            A machine's external names one far end of the Systems Tests'
            configuration/external.xmip (deploy/dsc/README.md; ADR-0028,
            amendment 2026-11-22). [far_ends.<family>] program is the
            program xmip-system-test-external built for that family, which
            msdsc places and registers on each such machine
            (far-end.dsc.yaml); each far end's certificate is identity's
            folder of its name, New-XmipCertificate -Node.

        .PARAMETER Environment
            The environment file, as Read-XmipToml reads it.

        .PARAMETER Estate
            The estate's root.

        .PARAMETER Read
            What Get-XmipDeployEnvironment read: FarEnds, Programs and
            Identity are added to it.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment,

        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [hashtable] $Read
    )

    $Read['FarEnds'] = @(foreach ($machine in $Read.Machines) {
            [object] $on = @(Get-TomlValue -Node $Environment -Name 'machines' -Default @()) |
                Where-Object { (Get-TomlValue -Node $_ -Name 'name') -eq $machine['name'] } |
                Select-Object -First 1
            [string] $external = Get-TomlValue -Node $on -Name 'external' -Default ''
            if ($external) {
                @{ name = $external; machine = @{ name = $machine['name']
                        address = $machine['address']; family = $machine['image'].family } }
            }
        })
    $Read['Programs'] = @{}
    $Read['Identity'] = ''
    if ($Read.FarEnds.Count -eq 0) {
        return
    }
    $Read['Identity'] = Resolve-XmipDeployPath -Estate $Estate -Path (
        Get-TomlValue -Node $Environment -Name 'identity' -Default '')
    $given = Get-TomlValue -Node $Environment -Name 'far_ends' -Default $null
    foreach ($family in @($Read.FarEnds | ForEach-Object { $_.machine.family } |
            Sort-Object -Unique)) {
        $entry = Get-TomlValue -Node $given -Name $family -Default $null
        [string] $path = Resolve-XmipDeployPath -Estate $Estate -Path (
            Get-TomlValue -Node $entry -Name 'program' -Default '')
        if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw ("REFUSED: a far end on a $family machine needs [far_ends.$family] program, " +
                "xmip-system-test-external built for it: '$path'.")
        }
        $Read.Programs[$family] = @{ path = $path; file = Split-Path -Path $path -Leaf }
    }
}
