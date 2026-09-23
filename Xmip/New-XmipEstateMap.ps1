#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Generates doc/architecture/estate-map.md from architecture.toml.

.DESCRIPTION
    `repository-model.md` section 7 draws where the modules mount. It is
    hand-drawn, it covers the forty-one submodules, and it stops there — the
    manifest declares 330 repositories, and the 290 technologies appeared on
    no map at all. Being hand-drawn is also why it was wrong: it carried three
    unmounted modules and an off-by-one count until 2026-09-19.

    ADR-0020 clause 5 is why this is generated rather than written: a document
    that lists repositories is a second source of truth and will be wrong
    within a week. A view is not a second source: test/EstateMap.Test.ps1
    regenerates and fails when the committed map differs, the way
    test/Decision.Test.ps1 holds the decision index. ADR-0060.

    `Get-XmipEstateRepository.ps1` reads the estate; this renders it.

    Style: doc/governance/powershell-style.md
#>

# The domains, in reading order, and the order the map's sections take. This is
# the map's own shape rather than the manifest's, which is why it lives here.
# Technology is deliberately absent: a technology is drawn under the repository
# that hosts it, never in a list of its own.
[string[]] $script:XmipMapDomain = @(
    'Foundation'
    'Library'
    'Capability'
    'Operation'
    'Platform'
)

# The column the generated prose wraps at. Under the hundred the style rules
# gate, so the map passes the same line-length rule as everything else.
[int] $script:XmipMapWidth = 78


function Format-XmipMapLine {
    <#
        .SYNOPSIS
            One long line of words, wrapped to the map's width.

        .DESCRIPTION
            Greedy, on spaces, every line after the first carrying $Indent.
            The technology lists are the only thing here long enough to need
            it, and the style rules gate the generated file like any other.

        .PARAMETER Text
            The whole line, already joined.

        .PARAMETER Indent
            What a continuation line begins with.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Indent
    )

    [string[]] $line = @()
    [string] $current = ''

    foreach ($word in ($Text -split ' ')) {
        if ([string]::IsNullOrEmpty($current)) {
            $current = $word
            continue
        }

        if (($current.Length + 1 + $word.Length) -le $script:XmipMapWidth) {
            $current = "$current $word"
            continue
        }

        $line += $current
        $current = "$Indent$word"
    }

    if (-not [string]::IsNullOrEmpty($current)) {
        $line += $current
    }

    return $line
}


function New-XmipMapText {
    <#
        .SYNOPSIS
            The whole map, as one string.

        .DESCRIPTION
            Split from `New-XmipEstateMap` so that the cmdlet is about what a
            caller asked for — report or write — and this is about what the
            document is.

        .PARAMETER Manifest
            The parsed manifest, for its classifications and its retirements.

        .PARAMETER Repository
            Every declared repository.

        .PARAMETER Extra
            Submodules mounted here that the estate tree does not declare.

        .PARAMETER Source
            Every source file, for the tree's counts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Repository,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Extra,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [PSCustomObject[]] $Source
    )

    $classification = Get-TomlValue -Node $Manifest -Name 'classification' -Default $null

    [string[]] $line = @(New-XmipMapPreamble -Repository $Repository -Extra $Extra) + @(
        '## The count'
        ''
    ) + (New-XmipMapCount -Repository $Repository) + @('') +
        (New-XmipMapComposition) + @('---', '') +
        (New-XmipMapTree -Repository $Repository -Source $Source) + @('---', '')

    foreach ($name in $script:XmipMapDomain) {
        [hashtable] $section = @{
            Domain      = $name
            Repository  = $Repository
            Description = (Get-XmipMapDescription -Classification $classification -Domain $name)
        }

        $line += (New-XmipMapDomain @section) + @('---', '')
    }

    $line += New-XmipMapRetired -Retired @(
        Get-TomlValue -Node $Manifest -Name 'retired' -Default @()
    )

    return (($line -join "`n").TrimEnd() + "`n")
}


function New-XmipEstateMap {
    <#
        .SYNOPSIS
            Builds doc/architecture/estate-map.md from the manifest and the
            composed tree.

        .DESCRIPTION
            Returns the map as text. Reporting is the default and needs no
            ceremony to reach; `-Save` writes it to the map file, and
            `-WhatIf` says what it would write.

            Reading composition means reading the mounted modules, so a clone
            whose submodules are not initialized produces a map reporting every
            technology as uncomposed. That is true of that clone and false of
            the estate, which is why `test/EstateMap.Test.ps1` says to compose
            before reading its failure as a stale map.

        .PARAMETER Root
            The repository root. Defaults to the one this module was imported
            from.

        .PARAMETER Save
            Write the result to doc/architecture/estate-map.md.

        .EXAMPLE
            New-XmipEstateMap

        .EXAMPLE
            New-XmipEstateMap -Save
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string] $Root,

        [Parameter(Mandatory = $false)]
        [switch] $Save,

        # The same map as a page, for publishing where the owner reads it.
        # Html is returned, or with -Save written to .local-work, never to
        # doc/: a page is a view of the document, not a second document
        # (ADR-0060, amendment 2026-09-21).
        [Parameter(Mandatory = $false)]
        [ValidateSet('Markdown', 'Html')]
        [string] $Format = 'Markdown'
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $Root = Get-XmipRepositoryRoot
    }

    $manifest = Get-XmipManifest -Path (Join-Path $Root 'architecture.toml')
    [PSCustomObject[]] $repository = @(Get-XmipEstateRepository -Root $Root)
    [hashtable] $composed = Get-XmipEstateComposition -Root $Root

    [string[]] $declared = @($repository | ForEach-Object { $_.Name })
    [string[]] $extra = @($composed.Keys | Where-Object { $_ -notin $declared } | Sort-Object)

    [PSCustomObject[]] $source = @(Get-XmipSourceFile -Root $Root)

    [hashtable] $whole = @{
        Manifest   = $manifest
        Repository = $repository
        Extra      = $extra
        Source     = $source
    }

    [string] $text = (New-XmipMapText @whole)

    if ($Format -eq 'Html') {
        [hashtable] $page = @{
            Root       = $Root
            Repository = $repository
            Source     = $source
            Map        = $text
            Retired    = @(Get-TomlValue -Node $manifest -Name 'retired' -Default @())
        }

        [string] $html = New-XmipEstatePage @page

        if ($Save) {
            [string] $where = Join-Path $Root '.local-work/estate-map.html'
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $where) | Out-Null
            Set-Content -LiteralPath $where -Value $html -NoNewline -Encoding utf8
            Write-Host "OK       wrote $where"
        }

        return $html
    }

    if (-not $Save) {
        return $text
    }

    [string] $path = Join-Path $Root 'doc/architecture/estate-map.md'

    if ($PSCmdlet.ShouldProcess($path, 'Write the generated estate map')) {
        Set-Content -LiteralPath $path -Value $text -NoNewline -Encoding utf8

        [int] $mounted = @($repository | Where-Object { $_.Mounted }).Count

        Write-Host "OK       wrote $path, $($repository.Count) declared, $mounted mounted"
    }

    return $text
}
