#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Each module repository's workflow, `.github/workflows/verify.yml`,
    written from the template the repository's language is made from.

.DESCRIPTION
    A module builds only inside the estate and takes everything else every
    crate shares from the root (ADR-0016, amendment 2026-11-27). GitHub runs
    a repository's workflow only from that repository's own folder, so the
    workflow is the one file each keeps: written from
    `template/<language>` by Sync-XmipEstate -Workflow, and held identical
    to it by test/Workflow.Test.ps1. A repository takes the template of the
    language its own entry in architecture.toml declares (ADR-0058,
    amendment 2026-11-17), and one whose language no template is made for,
    an example in C, Go, Java or Python, is written none (ADR-0016,
    amendment 2026-11-28).

    Style: doc/governance/powershell-style.md
#>

# The workflows that verify a second language beside the crate, each its
# repository's own: the module boundary's .NET binding and surface, and the
# VS Code extension's TypeScript shell (ADR-0052 clause 6).
[string[]] $script:XmipWorkflowOwn = @('xmip-core-abi', 'xmip-core-gui-vscode')

# Where a repository keeps its workflow, a template too.
[string] $script:XmipWorkflowPath = '.github/workflows/verify.yml'


function Get-XmipWorkflowPlan {
    <#
        .SYNOPSIS
            Each module repository holding a workflow, but the templates, the
            repositories whose language no template is made for and those
            whose workflow is their own: Path, its workflow,
            and Template, the template's it is written from, each from the
            root and `/`-separated.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    # Each declared repository's language as the manifest's reader resolves
    # it, and the languages a template is made for. A template is no
    # repository of the estate's tree, so it has no language here.
    $manifest = Get-XmipManifest -Path (Get-XmipEstateLayout -Root $RepositoryRoot).Manifest
    [hashtable] $languageOf = @{}

    foreach ($entry in @($manifest.repositories)) {
        $languageOf[[string] $entry.name] = [string] $entry.primaryCrate.language
    }

    $templates = Get-TomlValue -Node $manifest.crate -Name 'template' -Default @{}
    [string[]] $made = @(Get-TomlKey -Node $templates)

    foreach ($mounted in @(Get-XmipSubmodule -Root $RepositoryRoot -Recurse)) {
        [string] $language = [string] $languageOf[$mounted.Repository]

        if ($language -notin $made) {
            continue
        }

        [string] $template = "template/$language/$script:XmipWorkflowPath"
        [string] $path = "$($mounted.Path)/$script:XmipWorkflowPath"
        [bool] $held = Test-Path -LiteralPath (Join-Path $RepositoryRoot $path) -PathType Leaf

        [bool] $own = $mounted.Repository -in $script:XmipWorkflowOwn

        if (-not $held -or $own -or $path -eq $template) {
            continue
        }

        [pscustomobject]@{ Path = $path; Template = $template }
    }
}


function Write-XmipWorkflow {
    <#
        .SYNOPSIS
            Each module's workflow written from its template where the two
            differ: safe to run twice.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter()]
        [string] $RepositoryRoot = (Get-XmipRepositoryRoot)
    )

    foreach ($planned in @(Get-XmipWorkflowPlan -RepositoryRoot $RepositoryRoot)) {
        [string] $template = Join-Path -Path $RepositoryRoot -ChildPath $planned.Template
        [hashtable] $written = @{
            Path    = Join-Path -Path $RepositoryRoot -ChildPath $planned.Path
            Content = [System.IO.File]::ReadAllBytes($template)
            What    = 'Workflow'
        }
        Write-XmipChangedFile @written
    }
}
