#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Add-XmipDeployImage {
    <#
        .SYNOPSIS
            The installation image each machine's os names, and the tools
            Microsoft DSC is brought to each machine with, found on this host
            under the image folder, added to the host facts: Images, os to
            path, and Tools, family to pwsh and dsc, each a path and its
            SHA-256. Refused in words where one is not there.

        .DESCRIPTION
            An image is found by the SHA-256 the cluster file gives it
            ([environment.images.<os>] sha256), never by a path, which is
            the host's: every .iso under the folder is read once, its
            SHA-256 kept by its path, length and time of writing (Hashes),
            so a later run reads none of an image's gigabytes again. A tool
            is found by the file name prerequisite.toml gives it,
            [prerequisite.powershell.archive] and [prerequisite.dsc.archive],
            for each family a document is applied on: the nodes', the far
            ends', the domain controller's and the gateway's machines; and
            checked against the SHA-256 it gives.

        .PARAMETER Facts
            The host facts, Get-XmipDeployHost's: ImageFolder and Hashes read,
            Images and Tools added.

        .PARAMETER Content
            The cluster file's [environment].

        .PARAMETER Machines
            The machines, as Resolve-XmipDeployMachine resolves them.

        .PARAMETER Technology
            msdsc or ansible; Ansible brings no tool.

        .PARAMETER Estate
            The estate's root, where prerequisite.toml is.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Facts,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Content,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable[]] $Machines,

        [Parameter(Mandatory)]
        [string] $Technology,

        [Parameter(Mandatory)]
        [string] $Estate
    )

    [string] $folder = $Facts.ImageFolder
    $images = Get-TomlValue -Node $Content -Name 'images' -Default $null
    $Facts['Images'] = @{}
    foreach ($os in @($Machines | ForEach-Object { $_.os } | Sort-Object -Unique)) {
        $image = Get-TomlValue -Node $images -Name $os
        [string] $sha256 = Get-TomlValue -Node $image -Name 'sha256' -Default ''
        $sha256 = $sha256.ToLowerInvariant()
        [hashtable] $sought = @{ Folder = $folder; Sha256 = $sha256; Hashes = $Facts.Hashes }
        [string] $path = Find-XmipDeployFile @sought -Filter '*.iso'
        if (-not $path) {
            throw ("REFUSED: no image under $folder has the SHA-256 [environment.images.$os] " +
                "gives, $sha256`: put the publisher's ISO there, or name the folder that holds " +
                'it with -ImageFolder.')
        }
        $Facts.Images[$os] = $path
    }
    $Facts['Tools'] = @{ Linux = @{}; Windows = @{} }
    if ($Technology -ne 'msdsc') {
        return
    }
    [string[]] $applied = @(Get-TomlValue -Node $Content -Name 'domain_controller' -Default '') +
        @(Get-TomlValue -Node $Content -Name 'gateway' -Default '')
    [string[]] $families = @($Machines | Where-Object {
            $_.kind -ne 'machine' -or $_.name -in $applied } | ForEach-Object { $_.family } |
        Sort-Object -Unique)
    $prerequisite = Read-XmipToml -Path (Join-Path $Estate $script:XmipPrerequisiteName)
    $listed = Get-TomlValue -Node $prerequisite -Name 'prerequisite'
    foreach ($family in $families) {
        foreach ($tool in @(@('pwsh', 'powershell'), @('dsc', 'dsc'))) {
            $declared = Get-TomlValue -Node $listed -Name $tool[1] -Default $null
            $archives = Get-TomlValue -Node $declared -Name 'archive' -Default $null
            $archive = Get-TomlValue -Node $archives -Name $family.ToLowerInvariant() -Default $null
            [string] $file = Get-TomlValue -Node $archive -Name 'file' -Default ''
            [string] $sha256 = Get-TomlValue -Node $archive -Name 'sha256' -Default ''
            $sha256 = $sha256.ToLowerInvariant()
            [hashtable] $sought = @{ Folder = $folder; Sha256 = $sha256; Hashes = $Facts.Hashes }
            [string] $path = if ($file) { Find-XmipDeployFile @sought -Filter $file }
            if (-not $path) {
                throw ("REFUSED: msdsc brings DSC to each $family machine it applies a " +
                    "document on: $file, from its GitHub release, under $folder with the " +
                    "SHA-256 [prerequisite.$($tool[1]).archive] gives, $sha256.")
            }
            $Facts.Tools[$family][$tool[0]] = @{ path = $path; sha256 = $sha256 }
        }
    }
}

function Find-XmipDeployFile {
    <#
        .SYNOPSIS
            The first file under -Folder, by -Filter, whose SHA-256 is
            -Sha256; empty where none is or the folder is not there. A
            file's SHA-256 is read once and kept in -Hashes by its path,
            with its length and time of writing, and read again only where
            either changed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Folder,

        [Parameter(Mandatory)]
        [string] $Filter,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Sha256,

        [Parameter(Mandatory)]
        [hashtable] $Hashes
    )

    if (-not $Sha256 -or -not (Test-Path -LiteralPath $Folder -PathType Container)) {
        return ''
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Folder -Recurse -File -Filter $Filter |
            Sort-Object FullName)) {
        [string] $written = $file.LastWriteTimeUtc.Ticks.ToString()
        $known = if ($Hashes.ContainsKey($file.FullName)) { $Hashes[$file.FullName] }
        if ($null -eq $known -or [string] $known['written'] -ne $written -or
            [long] $known['length'] -ne $file.Length) {
            [string] $read = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            $known = @{ length = $file.Length; written = $written
                sha256 = $read.ToLowerInvariant() }
            $Hashes[$file.FullName] = $known
        }
        if ([string] $known['sha256'] -eq $Sha256) {
            return $file.FullName
        }
    }
    return ''
}
