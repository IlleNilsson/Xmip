#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The brand carried to every surface: the Windows icon and resource made
    from the mark, and each copy a repository of its own needs.

.DESCRIPTION
    asset/brand is the one source (asset/brand/README.md). What a surface
    needs that the source does not hold as such is made here from its PNGs,
    never redrawn: xmip-x.ico packs the mark at 16 to 256, each PNG as it
    is, and xmip-x.res holds that icon as a Windows resource a Rust
    executable links. asset/brand/brand.xmip names each surface, the file
    that shows the mark and, where the surface is a repository of its own,
    the copy it keeps; Sync-XmipEstate -Brand writes them, and
    test/Brand.Test.ps1 fails where one differs from what this makes.

    Style: doc/governance/powershell-style.md
#>

# The sizes a Windows icon holds; 512 is past what the format says.
[int[]] $script:XmipIconSize = @(16, 32, 48, 64, 128, 256)

function ConvertTo-XmipIcon {
    # An ICO container: its directory, then each PNG whole, as Windows reads
    # PNG images in an icon since Vista.
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Brand
    )

    [byte[][]] $images = @(Get-XmipIconImage -Brand $Brand)
    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    $writer.Write([uint16] 0)
    $writer.Write([uint16] 1)
    $writer.Write([uint16] $images.Count)
    [uint32] $offset = 6 + 16 * $images.Count

    for ([int] $at = 0; $at -lt $images.Count; $at++) {
        [int] $size = $script:XmipIconSize[$at]
        Write-XmipIconEntry -Writer $writer -Size $size -Length $images[$at].Length
        $writer.Write([uint32] $offset)
        $offset += [uint32] $images[$at].Length
    }

    foreach ($image in $images) { $writer.Write($image) }
    $writer.Flush()
    , $stream.ToArray()
}

function ConvertTo-XmipIconResource {
    # A Windows resource file: the empty entry every one starts with, each
    # image as an RT_ICON numbered from 1, and one RT_GROUP_ICON, numbered 1,
    # naming them: what link.exe takes beside the objects of an executable.
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Brand
    )

    [byte[][]] $images = @(Get-XmipIconImage -Brand $Brand)
    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    Write-XmipResourceEntry -Writer $writer -Type 0 -Id 0 -Flags 0 -Data ([byte[]]::new(0))

    for ([int] $at = 0; $at -lt $images.Count; $at++) {
        [hashtable] $entry = @{ Type = 3; Id = $at + 1; Flags = 0x1010; Data = $images[$at] }
        Write-XmipResourceEntry -Writer $writer @entry
    }

    $group = [System.IO.MemoryStream]::new()
    $grouped = [System.IO.BinaryWriter]::new($group)
    $grouped.Write([uint16] 0)
    $grouped.Write([uint16] 1)
    $grouped.Write([uint16] $images.Count)

    for ([int] $at = 0; $at -lt $images.Count; $at++) {
        [int] $size = $script:XmipIconSize[$at]
        Write-XmipIconEntry -Writer $grouped -Size $size -Length $images[$at].Length
        $grouped.Write([uint16] ($at + 1))
    }

    $grouped.Flush()
    Write-XmipResourceEntry -Writer $writer -Type 14 -Id 1 -Flags 0x1030 -Data $group.ToArray()
    $writer.Flush()
    , $stream.ToArray()
}

function Get-XmipIconImage {
    # Each size's PNG of the mark, as asset/brand/icon holds it.
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Brand
    )

    foreach ($size in $script:XmipIconSize) {
        , [System.IO.File]::ReadAllBytes((Join-Path $Brand "icon/xmip-x-$size.png"))
    }
}

function Write-XmipIconEntry {
    # The twelve bytes an icon's directory and a group's share for one
    # image: its size (0 meaning 256), no palette, one plane, 32 bits, and
    # its length.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.BinaryWriter] $Writer,

        [Parameter(Mandatory = $true)]
        [int] $Size,

        [Parameter(Mandatory = $true)]
        [int] $Length
    )

    [byte] $side = if (256 -le $Size) { 0 } else { $Size }
    $Writer.Write($side)
    $Writer.Write($side)
    $Writer.Write([byte] 0)
    $Writer.Write([byte] 0)
    $Writer.Write([uint16] 1)
    $Writer.Write([uint16] 32)
    $Writer.Write([uint32] $Length)
}

function Write-XmipResourceEntry {
    # One entry of a resource file: its header, the type and name by number,
    # language neutral, and its data padded to four bytes.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.BinaryWriter] $Writer,

        [Parameter(Mandatory = $true)]
        [int] $Type,

        [Parameter(Mandatory = $true)]
        [int] $Id,

        [Parameter(Mandatory = $true)]
        [int] $Flags,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]] $Data
    )

    $Writer.Write([uint32] $Data.Length)
    $Writer.Write([uint32] 32)
    $Writer.Write([uint16] 0xFFFF)
    $Writer.Write([uint16] $Type)
    $Writer.Write([uint16] 0xFFFF)
    $Writer.Write([uint16] $Id)
    $Writer.Write([uint32] 0)
    $Writer.Write([uint16] $Flags)
    $Writer.Write([uint16] 0)
    $Writer.Write([uint32] 0)
    $Writer.Write([uint32] 0)
    $Writer.Write($Data)
    [int] $padding = (4 - $Data.Length % 4) % 4
    if (0 -lt $padding) { $Writer.Write([byte[]]::new($padding)) }
}

function Get-XmipBrandSurface {
    # Each surface asset/brand/brand.xmip names: what it shows, from where,
    # the copy it keeps, if any, and the file that names it.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Root = (Get-XmipRepositoryRoot)
    )

    $brand = Read-XmipToml -Path (Join-Path $Root 'asset/brand/brand.xmip')

    foreach ($surface in @($brand['surface'])) {
        [pscustomobject] @{
            Name  = [string] $surface['name']
            From  = [string] $surface['from']
            Copy  = if ($surface.Contains('copy')) { [string] $surface['copy'] } else { '' }
            In    = [string] $surface['in']
            Names = [string] $surface['names']
        }
    }
}

function Write-XmipBrand {
    # What is made from the mark written beside it, then each surface's copy,
    # where it differs: safe to run twice.
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string] $Root = (Get-XmipRepositoryRoot)
    )

    [string] $brand = Join-Path $Root 'asset/brand'
    [hashtable] $made = @{
        'xmip-x.ico' = ConvertTo-XmipIcon -Brand $brand
        'xmip-x.res' = ConvertTo-XmipIconResource -Brand $brand
    }

    foreach ($name in $made.Keys) {
        Write-XmipBrandFile -Path (Join-Path $brand $name) -Content $made[$name]
    }

    foreach ($surface in @(Get-XmipBrandSurface -Root $Root | Where-Object Copy)) {
        [byte[]] $content = [System.IO.File]::ReadAllBytes((Join-Path $brand $surface.From))
        Write-XmipBrandFile -Path (Join-Path $Root $surface.Copy) -Content $content
    }
}

function Write-XmipBrandFile {
    # One file written where its bytes differ, said so.
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [byte[]] $Content
    )

    if (Test-Path -LiteralPath $Path) {
        [byte[]] $held = [System.IO.File]::ReadAllBytes($Path)
        if ([System.Linq.Enumerable]::SequenceEqual($held, $Content)) { return }
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Write the brand')) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
        [System.IO.File]::WriteAllBytes($Path, $Content)
        Write-XmipStep -Message "Brand: $Path"
    }
}
