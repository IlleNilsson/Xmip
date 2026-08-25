#requires -PSEdition Core
#requires -Version 7.6

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
    Xmip-Estate -Create -Configure -WhatIf
#>
function Xmip-Estate {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch] $Create,
        [switch] $Configure,
        [switch] $IncludeReserved,
        [switch] $Report,
        [string] $ManifestPath = (Join-Path $PSScriptRoot 'architecture.toml'),
        [string] $WorkingDirectory = (Join-Path $PSScriptRoot '.xmip-work'),
        [string] $ReportPath,
        [string] $GitHubToken = $env:GITHUB_TOKEN,
        [string] $GitHubApiBaseUri = 'https://api.github.com',
        [switch] $PassThru
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    if (-not $ReportPath) { $ReportPath = Join-Path $WorkingDirectory 'architecture-report.json' }

    function Assert-Command([string] $Name) {
        if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
            throw "Required command '$Name' was not found."
        }
    }

    function Invoke-Native {
        param(
            [Parameter(Mandatory)] [string] $FilePath,
            [string[]] $Arguments = @(),
            [string] $At = '',
            [switch] $CaptureOutput
        )

        $previous = $PWD
        try {
            if ($At) { Set-Location $At }
            if ($CaptureOutput) {
                $output = & $FilePath @Arguments 2>&1
            }
            else {
                & $FilePath @Arguments
            }
            if ($LASTEXITCODE -ne 0) {
                $details = if ($CaptureOutput) { "`n$($output -join "`n")" } else { '' }
                throw "Command failed: $FilePath $($Arguments -join ' ')$details"
            }
            if ($CaptureOutput) { return @($output) }
        }
        finally {
            Set-Location $previous
        }
    }

    function Get-GitHubHeaders {
        $headers = @{
            Accept = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28'
            'User-Agent' = 'Xmip-Architecture-Reconciler'
        }
        if ($GitHubToken) { $headers.Authorization = "Bearer $GitHubToken" }
        return $headers
    }

    function Invoke-GitHubApi {
        param(
            [Parameter(Mandatory)] [ValidateSet('GET','POST','PATCH','PUT','DELETE')] [string] $Method,
            [Parameter(Mandatory)] [string] $Path,
            $Body,
            # A 404 when probing for a repository is the answer, not a failure.
            # Without this every absent repository throws, and a first run
            # writes five hundred lines of TerminatingError into a transcript
            # for a result that is entirely expected.
            [ref] $StatusCode
        )

        $uri = if ($Path -match '^https?://') {
            $Path
        }
        else {
            "$($GitHubApiBaseUri.TrimEnd('/'))/$($Path.TrimStart('/'))"
        }

        $parameters = @{
            Method = $Method
            Uri = $uri
            Headers = Get-GitHubHeaders
            ErrorAction = 'Stop'
        }
        if ($StatusCode) {
            $parameters.SkipHttpErrorCheck = $true
            $parameters.StatusCodeVariable = 'responseStatus'
        }
        if ($PSBoundParameters.ContainsKey('Body')) {
            $parameters.ContentType = 'application/json'
            $parameters.Body = $Body | ConvertTo-Json -Depth 50
        }
        $response = Invoke-RestMethod @parameters
        if ($StatusCode) { $StatusCode.Value = $responseStatus }
        return $response
    }

    function Test-GitHubRepositoryExists {
        param(
            [Parameter(Mandatory)] [string] $Owner,
            [Parameter(Mandatory)] [string] $Name
        )

        $status = 0
        $repository = Invoke-GitHubApi GET "/repos/$Owner/$Name" -StatusCode ([ref] $status)

        if ($status -eq 404) { return [pscustomobject]@{ Exists = $false; Repository = $null } }
        if ($status -ge 400) {
            throw "GitHub returned $status for /repos/$Owner/$Name$(if ($repository.message) { ": $($repository.message)" })"
        }
        return [pscustomobject]@{ Exists = $true; Repository = $repository }
    }

    function Get-ActualRepositories {
        param([Parameter(Mandatory)] $Manifest)

        $owner = [string](Get-PropertyValue $Manifest 'owner')
        $actual = [Collections.Generic.List[object]]::new()
        foreach ($repository in @(Get-PropertyValue $Manifest 'repositories' @())) {
            $name = [string](Get-PropertyValue $repository 'name')
            $result = Test-GitHubRepositoryExists -Owner $owner -Name $name
            if ($result.Exists) {
                $actual.Add($result.Repository)
            }
        }
        return @($actual.ToArray())
    }

    function New-TransactionReport($Manifest, $Actual) {
        $desired = @{}
        foreach ($repository in @(Get-PropertyValue $Manifest 'repositories' @())) {
            $desired[[string](Get-PropertyValue $repository 'name')] = $repository
        }

        $actualMap = @{}
        foreach ($repository in @(ConvertTo-Array $Actual)) {
            if ($null -ne $repository) {
                $actualMap[[string](Get-PropertyValue $repository 'name')] = $repository
            }
        }

        return [ordered]@{
            generatedAtUtc = [DateTime]::UtcNow.ToString('o')
            scriptVersion = $script:XmipVersion.ToString()
            schemaVersion = [string](Get-PropertyValue $Manifest 'schemaVersion' 'unversioned')
            architectureVersion = [string](Get-PropertyValue $Manifest 'architectureVersion' 'unversioned')
            owner = [string](Get-PropertyValue $Manifest 'owner')
            desiredCount = $desired.Count
            actualCount = $actualMap.Count
            missing = @($desired.Keys | Where-Object { -not $actualMap.ContainsKey($_) } | Sort-Object)
            unexpected = @()
            deprecated = @()
            retired = @()
            operations = [ordered]@{
                created = 0
                configured = 0
                metadataWritten = 0
                commits = 0
                pushes = 0
                skipped = 0
            }
        }
    }

    function New-XmipGitHubRepository {
        param(
            [Parameter(Mandatory)] $Repository,
            [Parameter(Mandatory)] [string] $Owner,
            [Parameter(Mandatory)] [ValidateSet('User','Organization')] [string] $OwnerType,
            [string] $Template
        )

        $name = [string](Get-PropertyValue $Repository 'name')
        $description = [string](Get-PropertyValue $Repository 'description')
        $github = Get-PropertyValue $Repository 'github' ([pscustomobject]@{})
        $visibility = [string](Get-PropertyValue $github 'visibility' 'public')
        if ($visibility -notin @('public','private','internal')) {
            throw "Unsupported GitHub visibility '$visibility' for '$name'."
        }
        if ($OwnerType -eq 'User' -and $visibility -eq 'internal') {
            throw "Visibility 'internal' is not valid for user-owned repository '$name'."
        }

        $settings = [ordered]@{
            has_issues = [bool](Get-PropertyValue $github 'hasIssues' $true)
            has_projects = [bool](Get-PropertyValue $github 'hasProjects' $false)
            has_wiki = [bool](Get-PropertyValue $github 'hasWiki' $false)
        }

        # The template is a Rust crate: Cargo.toml, src/lib.rs and a Rust workflow.
        # A module that is not a Rust crate must not be generated from it, or a
        # PowerShell module arrives holding a Cargo.toml. ADR-0014 clause 14.
        $primaryCrate = Get-PropertyValue $Repository 'primaryCrate' ([pscustomobject]@{})
        $language = [string](Get-PropertyValue $primaryCrate 'language' 'rust')
        if ($Template -and $language -ine 'rust') {
            Write-Warning "$name is language '$language', not rust. Creating it empty rather than from the Rust template; it needs its own scaffolding."
            $Template = ''
        }

        # A repository generated from the template starts with the licence, the
        # workflow and the layout every Xmip repository is supposed to have. A
        # blank one starts with nothing and someone has to remember to add them.
        if ($Template) {
            if ($Template -notmatch '^[^/]+/[^/]+$') {
                throw "Template must be owner/name, not '$Template'."
            }

            $body = [ordered]@{
                owner = $Owner
                name = $name
                description = $description
                include_all_branches = $false
                private = ($visibility -eq 'private')
            }

            $created = Invoke-GitHubApi POST "/repos/$Template/generate" $body

            # generate takes none of the feature switches, so they follow.
            $null = Invoke-GitHubApi PATCH "/repos/$Owner/$name" $settings
            return $created
        }

        $body = [ordered]@{
            name = $name
            description = $description
            private = ($visibility -eq 'private')
            auto_init = [bool](Get-PropertyValue $github 'autoInitialize' $true)
        }
        foreach ($key in $settings.Keys) { $body[$key] = $settings[$key] }
        if ($OwnerType -eq 'Organization') { $body.visibility = $visibility }

        $path = if ($OwnerType -eq 'Organization') { "/orgs/$Owner/repos" } else { '/user/repos' }
        return Invoke-GitHubApi POST $path $body
    }

    function Invoke-ConfigureRepositories {
        <#
            Repository settings only: description, topics and the feature switches.
            All of it is the GitHub API, so nothing is cloned and nothing is built.
            Crate content — Cargo.toml, lib.rs — is a different job needing a
            working tree.

            Idempotent by construction. Run it whenever the manifest changes and it
            reconciles what drifted, including repositories created before a
            setting existed.
        #>
        param(
            [Parameter(Mandatory)] $Manifest,
            [Parameter(Mandatory)] [System.Collections.IDictionary] $Report
        )

        if (-not $GitHubToken) {
            throw '-Configure requires -GitHubToken or GITHUB_TOKEN.'
        }

        $owner = [string](Get-PropertyValue $Manifest 'owner')
        $missing = [Collections.Generic.HashSet[string]]::new(
            [string[]]@($Report.missing), [StringComparer]::OrdinalIgnoreCase)

        foreach ($repository in @(Get-PropertyValue $Manifest 'repositories' @())) {
            $name = [string](Get-PropertyValue $repository 'name')

            # Nothing to configure on a repository that does not exist.
            if ($missing.Contains($name)) { continue }

            $github = Get-PropertyValue $repository 'github' ([pscustomobject]@{})
            $topics = @(ConvertTo-Array (Get-PropertyValue $github 'topics' @()) |
                    ForEach-Object { ([string]$_).ToLowerInvariant() } |
                    Where-Object { $_ -match '^[a-z0-9][a-z0-9-]{0,49}$' } |
                    Select-Object -Unique)

            $settings = [ordered]@{
                description = [string](Get-PropertyValue $repository 'description')
                has_issues = [bool](Get-PropertyValue $github 'hasIssues' $true)
                has_projects = [bool](Get-PropertyValue $github 'hasProjects' $false)
                has_wiki = [bool](Get-PropertyValue $github 'hasWiki' $false)
            }

            if (-not $PSCmdlet.ShouldProcess("$owner/$name", 'Configure repository')) {
                $Report.operations.skipped++
                continue
            }

            Write-Step "Configuring $owner/$name"
            $null = Invoke-GitHubApi PATCH "/repos/$owner/$name" $settings

            # Topics are their own endpoint and replace wholesale, which is what
            # makes the manifest authoritative rather than additive.
            if ($topics.Count) {
                $null = Invoke-GitHubApi PUT "/repos/$owner/$name/topics" ([ordered]@{ names = $topics })
            }

            $Report.operations.configured++
        }
    }

    function Invoke-CreateRepositories {
        param(
            [Parameter(Mandatory)] $Manifest,
            [Parameter(Mandatory)] [System.Collections.IDictionary] $Report
        )

        if (-not $GitHubToken) {
            throw '-Create requires -GitHubToken or GITHUB_TOKEN.'
        }

        $owner = [string](Get-PropertyValue $Manifest 'owner')
        $ownerInfo = Invoke-GitHubApi GET "/users/$owner"
        $ownerType = [string](Get-PropertyValue $ownerInfo 'type')
        if ($ownerType -notin @('User','Organization')) {
            throw "Unsupported GitHub owner type '$ownerType' for '$owner'."
        }

        if ($ownerType -eq 'User') {
            $currentUser = Invoke-GitHubApi GET '/user'
            $currentLogin = [string](Get-PropertyValue $currentUser 'login')
            if ($currentLogin -ine $owner) {
                throw "Authenticated GitHub user '$currentLogin' cannot create repositories for '$owner'."
            }
        }

        # crate.template in schema 2.0, cratePolicy.template in schema 1.
        $template = [string](Get-TomlValue (Get-TomlValue $Manifest 'crate' $null) 'template' `
            ([string](Get-PropertyValue (Get-PropertyValue $Manifest 'cratePolicy') 'template' '')))

        if ($template) {
            $templateInfo = Invoke-GitHubApi GET "/repos/$template"
            if (-not [bool](Get-PropertyValue $templateInfo 'is_template' $false)) {
                throw "'$template' is not marked as a template repository. Enable Settings, Template repository on it, or clear crate.template to create blank repositories."
            }
            Write-Step "Creating from template $template"
        }
        else {
            Write-Warning 'No crate.template in the manifest. Repositories will be created blank, with no licence, workflow or layout.'
        }

        $desired = @{}
        foreach ($repository in @(Get-PropertyValue $Manifest 'repositories' @())) {
            $desired[[string](Get-PropertyValue $repository 'name')] = $repository
        }

        foreach ($name in @($Report.missing)) {
            $repository = $desired[$name]
            if ($null -eq $repository) { throw "Missing repository definition for '$name'." }

            $maturity = [string](Get-PropertyValue $repository 'maturity' 'reserved')
            if ($maturity -eq 'reserved' -and -not $IncludeReserved) {
                Write-Warning "SKIPPED RESERVED: $name"
                $Report.operations.skipped++
                continue
            }

            $existing = Test-GitHubRepositoryExists -Owner $owner -Name $name
            if ($existing.Exists) {
                Write-Step "Repository already exists: $owner/$name"
                $Report.actualCount++
                $Report.missing = @($Report.missing | Where-Object { $_ -ine $name })
                $Report.operations.skipped++
                continue
            }

            if (-not $PSCmdlet.ShouldProcess("$owner/$name", 'Create GitHub repository')) {
                $Report.operations.skipped++
                continue
            }

            Write-Step "Creating repository $owner/$name"
            $created = New-XmipGitHubRepository -Repository $repository -Owner $owner -OwnerType $ownerType -Template $template
            $createdName = [string](Get-PropertyValue $created 'name')
            if ($createdName -ine $name) {
                throw "GitHub returned repository '$createdName' while creating '$name'."
            }

            $verification = Test-GitHubRepositoryExists -Owner $owner -Name $name
            if (-not $verification.Exists) {
                throw "Repository '$owner/$name' was not visible after creation."
            }

            $Report.operations.created++
            $Report.actualCount++
            $Report.missing = @($Report.missing | Where-Object { $_ -ine $name })
        }
    }












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
    $operating = $Create -or $Configure

    $manifest = Get-XmipManifest $ManifestPath
    Test-XmipManifest $manifest
    $actual = @(Get-ActualRepositories -Manifest $manifest)
    $drift = New-TransactionReport $manifest $actual

    Write-Step "Drift: $($drift.missing.Count) missing, $($drift.unexpected.Count) unexpected"
    foreach ($name in $drift.missing) { Write-Warning "MISSING: $name" }
    foreach ($name in $drift.unexpected) { Write-Warning "UNEXPECTED: $name" }

    if ($Create) { Invoke-CreateRepositories -Manifest $manifest -Report $drift }
    if ($Configure) { Invoke-ConfigureRepositories -Manifest $manifest -Report $drift }
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
