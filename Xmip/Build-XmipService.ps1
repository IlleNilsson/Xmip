#requires -PSEdition Core
#requires -Version 7.6.5

function Build-XmipService {
    <#
        .SYNOPSIS
            Builds xmip-service for a site: the features its target, roles
            and domains need, and nothing else.

        .DESCRIPTION
            A site, deploy/site/<name>.toml, picks one target (device, edge,
            computer, server or hosted), the node roles it serves and the
            domains it integrates; the profiles under deploy/profile say what
            each brings (ADR-0015, amendment 2026-10-01). The build carries
            the target's features, every role's (executing is receiving,
            processing and sending), each domain technology the root crate
            links through a feature, and xmip-service's own required
            features, which its [[bin]] entry in Cargo.toml declares. A
            domain technology xmip-service has no feature for yet is said
            under Unlinked, not refused.

            The target vetoes. A role or a domain needing a feature the
            target refuses is REFUSED, naming the role or domain, the feature
            and the target's reason; a target that cannot run xmip-service
            at all, the device, is REFUSED with what builds for it instead:
            xmip-core alone, no_std.

            The build sets what is possible; the node's TOML picks from it at
            run time. Cargo runs at the estate root, in CARGO_TARGET_DIR when
            that is set. Returns the plan: Site, Target, Roles, Domains,
            Features, Unlinked and Command.

        .PARAMETER Site
            A site's name under deploy/site, or the path of a site file.

        .PARAMETER CargoArgument
            Further arguments for cargo after the subcommand: --release,
            --target <triple>, --locked, --config <file>.

        .EXAMPLE
            Build-XmipService -Site hospital-interface -WhatIf

            Resolves the hospital's server site and says the cargo command
            it would run, building nothing.

        .EXAMPLE
            Build-XmipService -Site factory-gateway -CargoArgument '--release'

            Builds the edge gateway's xmip-service, optimized.

        .EXAMPLE
            $arm = '--target', 'aarch64-unknown-linux-gnu'
            Build-XmipService -Site mill.toml -CargoArgument $arm

            Builds a site kept outside the estate for a 64-bit ARM Linux
            machine: the edge target's first triple.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Site,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $CargoArgument = @()
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    trap {
        Write-XmipAudit -Action 'Build-XmipService' -ErrorRecord $_
        break
    }

    [string] $root = Get-XmipRepositoryRoot
    $manifest = Get-XmipManifest -Path (Join-Path $root 'architecture.toml')
    [hashtable] $asked = @{
        Root          = $root
        Site          = $Site
        Manifest      = $manifest
        CargoArgument = $CargoArgument
    }
    $plan = Resolve-XmipSite @asked

    if ($plan.Unlinked.Count -gt 0) {
        Write-Verbose "Not linked by xmip-service yet: $($plan.Unlinked -join ', ')"
    }

    if ($PSCmdlet.ShouldProcess("site $($plan.Site)", $plan.Command)) {
        Write-XmipAudit -Action 'Build-XmipService' -Phase Begin -Property @{
            Site    = $plan.Site
            Command = $plan.Command
        }
        Invoke-XmipServiceBuild -Root $root -Argument $plan.Argument
        Write-XmipStep -Message "OK: built xmip-service for site $($plan.Site)"
        Write-XmipAudit -Action 'Build-XmipService' -Phase Finished -Property @{ Site = $plan.Site }
    }

    return $plan
}


function Invoke-XmipServiceBuild {
    <#
        .SYNOPSIS
            Runs cargo at the estate root with a resolved site's arguments;
            FAILED in words when cargo does.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string[]] $Argument
    )

    Push-Location -LiteralPath $Root

    try {
        & cargo @Argument 2>&1 | ForEach-Object { Write-Host "     cargo| $_" }

        if ($LASTEXITCODE -ne 0) {
            throw "FAILED: cargo $($Argument -join ' ') exited $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}
