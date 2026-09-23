#requires -PSEdition Core
#requires -Version 7.6.5

# Dot-sourced by Xmip.psm1, which supplies the shared manifest reader.
# Import-Module ./Xmip.psm1 rather than running this file directly.

<#
.SYNOPSIS
    Reconciles the Xmip repository estate on GitHub with architecture.toml.

.DESCRIPTION
    Remote only. Creates repositories that the manifest names and GitHub does
    not have, and configures description, topics and features on those that
    exist. Nothing is cloned and nothing is built.

    An operation switch means do it. -WhatIf means do not. There is no
    -Apply: git does not work that way and neither should this.

.EXAMPLE
    Import-Module ./Xmip.psm1
    Sync-XmipEstate -Create -Configure -WhatIf
#>
<#
    .SYNOPSIS
    The path a repository mounts at inside its owner, or '' if it has none.

    .DESCRIPTION
    Two levels, per ADR-0016 and section 14 of the repository creation
    blueprint.

    Depth two mounts under Xmip, grouped by provider and then by architectural
    domain, because that layout exists for human navigation:

        xmip-core-transport   ->  module/core/capability/transport
        xmip-core-journey     ->  module/core/foundation/journey

    Depth three mounts directly inside its own parent capability, because at
    that level the parent is the grouping and everything in that repository is
    the module (ADR-0016, amended 2026-09-07):

        xmip-core-transport-kafka  ->  kafka

    The name is the TOML tree path with dots as hyphens, so the mount name is
    the last segment and the owner is the name minus that segment.

    **Provider before purpose, with no exception.** The owner, 2026-09-23:
    *Provider before purpose* — the inventor is one provider and others plug
    in beside him. A first draft kept what starts a node (`foundation`,
    `platform`) without a provider; that left two slicings in one tree, and
    it went the same day. Whatever a provider ships sits in one subtree of
    its own, so a third party can read its whole place from its name:

        xmip-core-node                   ->  module/core/foundation/node
        xmip-core-runtime                ->  module/core/platform/runtime
        xmip-core-transport              ->  module/core/capability/transport
        xmip-core-transport-kafka        ->  kafka, inside that
        xmip-<provider>-transport        ->  module/<provider>/capability/transport
        xmip-<provider>-transport-kafka  ->  kafka, inside that
        xmip-core-library-asn1           ->  module/core/library/asn1
#>
function Get-XmipMountPath {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        $Repository,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Declared
    )

    [string] $name = [string](Get-PropertyValue $Repository 'name')

    # An explicit mount wins over the computed path. Almost nothing declares one
    # — `module/<provider>/<domain>/<leaf>` below is right for a module. One
    # whose owner is reserved (a library, the Playground) mounts where it says.
    [string] $declaredMount = [string](Get-PropertyValue $Repository 'mount' '')
    if ('' -ne $declaredMount) {
        return [pscustomobject]@{ Owner = ''; Mount = $declaredMount }
    }

    [string] $owner = Get-XmipDeclaredOwner -Name $name -Declared $Declared
    [string] $leaf = $name

    if ('' -ne $owner) {
        $leaf = $name.Substring($owner.Length + 1)
    }
    elseif ($name.StartsWith('xmip-', [StringComparison]::OrdinalIgnoreCase)) {
        $leaf = $name.Substring(5)
    }

    # The provider is the second segment: xmip-<provider>-<module>.
    [string[]] $segment = $name.Split('-')
    [string] $provider = if ($segment.Count -ge 2 -and $segment[0] -ieq 'xmip') {
        $segment[1]
    }
    else {
        ''
    }

    # xmip-core is both a repository and the prefix every module carries, so a
    # module resolves to it. Modules mount under the estate root regardless —
    # ADR-0016 has Xmip pin every module directly.
    if (('' -eq $owner) -or ($owner -ieq 'xmip-core')) {
        [string] $domain = [string](
            Get-PropertyValue $Repository 'architecturalDomain' 'Capability'
        ).ToLowerInvariant()

        # The leaf is what follows the provider, whoever the provider is:
        # xmip-core-transport is transport, and so is any other provider's.
        # A name that is only a provider — xmip-core itself — is its own leaf.
        if ('' -ne $provider -and $segment.Count -gt 2) {
            $leaf = ($segment | Select-Object -Skip 2) -join '-'
        }

        # Only a name with no provider in it mounts without one.
        if ('' -eq $provider) {
            return [pscustomobject]@{ Owner = ''; Mount = "module/$domain/$leaf" }
        }

        return [pscustomobject]@{ Owner = ''; Mount = "module/$provider/$domain/$leaf" }
    }

    return [pscustomobject]@{ Owner = $owner; Mount = $leaf }
}


function Sync-XmipEstate {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch] $Create,
        [switch] $Configure,
        [switch] $Compose,
        # Not -Crate. One letter from -Create on the same cmdlet, where a typo
        # would create repositories instead of rewriting Cargo.toml.
        [switch] $Cargo,
        [switch] $IncludeReserved,
        [switch] $Report,
        # Restrict -Create to these repository names. Without it, -Create makes
        # every repository the manifest declares and GitHub lacks - which is
        # 200+ once the technology children are counted, and nobody has ever
        # wanted them all at once. Names must be declared in the manifest;
        # anything else is refused, not guessed at. Not -Name: three loops in
        # this function iterate $name, and a loop variable is never a
        # parameter - the gate that enforces it caught this parameter's first
        # spelling.
        [string[]] $Only = @(),
        [string] $ManifestPath = (Join-Path (Get-XmipRepositoryRoot) 'architecture.toml'),
        [string] $WorkingDirectory = (Join-Path (Get-XmipRepositoryRoot) '.ai-work'),
        [string] $ReportPath,
        [string] $GitHubToken = $env:GITHUB_TOKEN,
        [string] $GitHubApiBaseUri = 'https://api.github.com',
        [switch] $PassThru
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if (-not $ReportPath) { $ReportPath = Join-Path $WorkingDirectory 'architecture-report.json' }

    # The GitHub connection every helper is handed, rather than one they read
    # out of this function's scope. They were nested here and read it
    # unseen until 2026-09-22, when they became files of their own.
    [hashtable] $GitHub = @{ Token = $GitHubToken; BaseUri = $GitHubApiBaseUri }

    # ---------------------------------------------------------------------------
    # Schema 2.0. The tree is the data: a repository name is derived from its
    # position, so a name cannot drift from the structure that owns it.
    #
    #   platform.xmip-core                                    -> xmip-core
    #   xmip.core.transport         -> xmip-core-transport
    #   xmip.core.transport.kafka   -> xmip-core-transport-kafka
    #
    # The tree is flattened into the same repository shape schema 1 produced, so
    # everything downstream is untouched by which file it came from.
    #
    # ConvertFrom-Toml has returned a dictionary in one version and an object in
    # the next. Which one it is should not be a thing this script has an opinion
    # about, so it never asks directly.
    # ---------------------------------------------------------------------------

    # No operation switch means report only. That is the safe default and it
    # needs no ceremony to reach.
    $operating = $Create -or $Configure -or $Compose -or $Cargo

    $manifest = Get-XmipManifest $ManifestPath
    Test-XmipManifest $manifest
    $actual = @(Get-ActualRepositories -Manifest $manifest -GitHub $GitHub)
    $drift = New-TransactionReport $manifest $actual
    $split = Split-XmipDrift -Manifest $manifest -Missing @($drift.missing)

    Write-Step "Drift: $($split.actionable.Count) missing, $($drift.unexpected.Count) unexpected"

    foreach ($entry in @($split.actionable)) {
        Write-Warning "MISSING: $($entry.Name)  ($($entry.Maturity))"
    }

    foreach ($name in $drift.unexpected) {
        Write-Warning "UNEXPECTED: $name"
    }

    if (0 -lt $split.expected.Count) {
        [string] $note = '{0} reserved and not created, as designed. -IncludeReserved overrides.' -f
            $split.expected.Count

        Write-Step $note
    }

    if ($Create) {
        [hashtable] $creating = @{
            Manifest        = $manifest
            Report          = $drift
            GitHub          = $GitHub
            IncludeReserved = $IncludeReserved
            Only            = $Only
        }

        Invoke-CreateRepositories @creating
    }
    if ($Configure) {
        Invoke-ConfigureRepositories -Manifest $manifest -Report $drift -GitHub $GitHub
    }
    if ($Compose) { Invoke-Compose -Manifest $manifest -Actual $actual }
    if ($Cargo) { Invoke-Cargo }
    if (-not $operating) { Write-Step 'Reporting only; no operation selected.' }

    if ($Report) {
        $directory = Split-Path -Parent $ReportPath
        if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
        $drift | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $ReportPath -Encoding utf8NoBOM
        Write-Host "Report written: $ReportPath"
    }

    Write-Step "Estate reconciliation completed$(if (-not $operating) { ' (report only)' })"
    if ($PassThru) { [pscustomobject]$drift }

}
