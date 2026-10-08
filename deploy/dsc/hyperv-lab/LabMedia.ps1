#requires -PSEdition Core
#requires -Version 7.6.5
# The media the lab is built from, checked before Set changes anything: the
# operating systems' ISOs and the installers with their verified SHA256
# values, the lab's SSH key, and the files each guest is given. Nothing here
# is fetched; every file is the operator's, on the host.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-LabFile {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Sha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or
        $Sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw "Provide $Path locally and its verified SHA256 value in lab.json."
    }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Sha256) {
        throw "Checksum differs: $Path"
    }
}

function Assert-LabImage {
    <#
    .SYNOPSIS
    The ISO of every Os one family's machines run, present and as verified.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Windows', 'Linux')]
        [string] $Family
    )

    foreach ($os in @($Lab.Machines | Where-Object Family -eq $Family |
        ForEach-Object { $_.Os } | Select-Object -Unique)) {
        [hashtable] $image = $Lab.Images[$os]
        [string] $sha256 = if ($image.ContainsKey('Sha256')) { $image.Sha256 } else { '' }
        Assert-LabFile -Path $image.Path -Sha256 $sha256
    }
}

function Assert-LabMedia {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab
    )

    Assert-LabImage -Lab $Lab -Family Windows
    Assert-LabFile -Path $Lab.Development.PowerShellMsi -Sha256 $Lab.Development.Sha256
    if (-not (Test-Path -LiteralPath $Lab.Xmip.Cluster -PathType Leaf)) {
        throw "The lab cluster's xmip.toml is missing: $($Lab.Xmip.Cluster)"
    }
    [object[]] $nodes = @($Lab.Machines | Where-Object {
        $_.Role -eq 'Xmip' -and $_.Family -eq 'Windows'
    })
    [string] $program = $Lab.Xmip.WindowsService
    if ($nodes.Count -gt 0 -and -not (Test-Path -LiteralPath $program -PathType Leaf)) {
        throw "Build xmip-service for Windows first: $program"
    }
}

function Assert-LabLinuxMedia {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab
    )

    Assert-LabImage -Lab $Lab -Family Linux
    Assert-LabFile -Path $Lab.Linux.PowerShell.Path -Sha256 $Lab.Linux.PowerShell.Sha256
    Assert-LabFile -Path $Lab.Linux.Dsc.Path -Sha256 $Lab.Linux.Dsc.Sha256
    Get-LabPublicKey -Lab $Lab | Out-Null
    foreach ($tool in @('ssh', 'scp')) {
        if ($null -eq (Get-Command -Name $tool -CommandType Application -ErrorAction Ignore)) {
            throw "OpenSSH's $tool is missing on the host."
        }
    }
    foreach ($machine in @($Lab.Machines | Where-Object Family -eq 'Linux')) {
        foreach ($file in @(Get-LabLinuxMedia -Lab $Lab -Machine $machine).Values) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                throw "$($machine.Name) needs $file."
            }
        }
    }
}

function Get-LabLinuxMedia {
    <#
    .SYNOPSIS
    The files one Linux guest is given beyond the lab's own scripts, as the
    payload path each lands at, relative, to the host file it comes from.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [hashtable] $media = @{
        'powershell.rpm' = $Lab.Linux.PowerShell.Path
        'dsc.rpm' = $Lab.Linux.Dsc.Path
    }
    if ($Machine.Role -eq 'PostgreSql') {
        [string] $tls = $Lab.PostgreSql.Tls.Directory
        $media['tls/server.crt'] = Join-Path -Path $tls -ChildPath "$($Machine.Name).crt"
        $media['tls/server.key'] = Join-Path -Path $tls -ChildPath "$($Machine.Name).key"
        $media['tls/authority.pem'] = $Lab.PostgreSql.Tls.Authority
    }
    if ($Machine.Role -eq 'PostgreSql' -and -not $Machine.ContainsKey('StandbyOf')) {
        [string] $sql = Join-Path -Path $PSScriptRoot -ChildPath '../../database/postgresql'
        foreach ($script in @(Get-ChildItem -LiteralPath $sql -Filter '*.sql')) {
            $media["sql/$($script.Name)"] = $script.FullName
        }
    }
    if ($Machine.Role -eq 'Xmip') {
        $media['xmip/xmip.toml'] = $Lab.Xmip.Cluster
        $media['xmip/xmip-service'] = $Lab.Xmip.LinuxService
    }
    return $media
}
