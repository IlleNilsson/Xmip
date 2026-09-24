#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Creating the repositories the manifest declares and configuring the ones that exist.

.DESCRIPTION
    Nested inside Sync-XmipEstate until 2026-09-22, which made that one function
    719 lines against the 400 the estate allows a file, and let every helper
    read the GitHub token and address out of its scope unseen. Lifted when the
    owner asked for the estate to be consolidated; each now takes the
    connection it uses as a parameter, -GitHub.

    Style: doc/governance/powershell-style.md
#>

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

    [hashtable] $unexpectedQuery = @{
        Actual   = @($actualMap.Keys)
        Declared = @($desired.Keys)
        Template = @((Get-XmipTemplate -Manifest $Manifest).Values)
        Retired  = @(Get-XmipRetiredName -Manifest $Manifest)
    }

    return [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        scriptVersion = $script:XmipVersion.ToString()
        schemaVersion = [string](Get-PropertyValue $Manifest 'schemaVersion' 'unversioned')
        architectureVersion = [string](
            Get-PropertyValue $Manifest 'architectureVersion' 'unversioned'
        )
        owner = [string](Get-PropertyValue $Manifest 'owner')
        desiredCount = $desired.Count
        actualCount = @($actualMap.Keys | Where-Object { $desired.ContainsKey($_) }).Count
        missing = @($desired.Keys | Where-Object { -not $actualMap.ContainsKey($_) } | Sort-Object)

        unexpected = @(Get-XmipUnexpectedName @unexpectedQuery)
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
        [hashtable] $Template = @{},
        [Parameter(Mandatory)] [hashtable] $GitHub
    )

    $name = [string](Get-PropertyValue $Repository 'name')
    $description = [string](Get-PropertyValue $Repository 'description')
    $wanted = Get-PropertyValue $Repository 'github' ([pscustomobject]@{})
    $visibility = [string](Get-PropertyValue $wanted 'visibility' 'public')
    if ($visibility -notin @('public','private','internal')) {
        throw "Unsupported GitHub visibility '$visibility' for '$name'."
    }
    if ($OwnerType -eq 'User' -and $visibility -eq 'internal') {
        throw "Visibility 'internal' is not valid for user-owned repository '$name'."
    }

    $settings = [ordered]@{
        has_issues = [bool](Get-PropertyValue $wanted 'hasIssues' $true)
        has_projects = [bool](Get-PropertyValue $wanted 'hasProjects' $false)
        has_wiki = [bool](Get-PropertyValue $wanted 'hasWiki' $false)
    }

    # One template per language. A module generated from the wrong one
    # arrives holding a Cargo.toml it will never build. ADR-0014 clause 14.
    $primaryCrate = Get-PropertyValue $Repository 'primaryCrate' ([pscustomobject]@{})
    $language = [string](Get-PropertyValue $primaryCrate 'language' 'rust')
    [string] $chosen = ''

    if ($Template.ContainsKey($language)) {
        $chosen = [string] $Template[$language]
    }
    elseif ($Template.Count -gt 0) {
        [string] $warning = "$name is language '$language', which crate.template does not " +
            'cover. Creating it empty; it needs its own scaffolding.'

        Write-Warning $warning
    }

    # A repository generated from the template starts with the licence, the
    # workflow and the layout every Xmip repository is supposed to have. A
    # blank one starts with nothing and someone has to remember to add them.
    if ($chosen) {
        if ($chosen -notmatch '^[^/]+/[^/]+$') {
            throw "Template must be owner/name, not '$chosen'."
        }

        $body = [ordered]@{
            owner = $Owner
            name = $name
            description = $description
            include_all_branches = $false
            private = ($visibility -eq 'private')
        }

        $created = Invoke-GitHubApi POST "/repos/$chosen/generate" $body -GitHub $GitHub

        # generate takes none of the feature switches, so they follow.
        $null = Invoke-GitHubApi PATCH "/repos/$Owner/$name" $settings -GitHub $GitHub
        return $created
    }

    $body = [ordered]@{
        name = $name
        description = $description
        private = ($visibility -eq 'private')
        auto_init = [bool](Get-PropertyValue $wanted 'autoInitialize' $true)
    }
    foreach ($key in $settings.Keys) { $body[$key] = $settings[$key] }
    if ($OwnerType -eq 'Organization') { $body.visibility = $visibility }

    $path = if ($OwnerType -eq 'Organization') { "/orgs/$Owner/repos" } else { '/user/repos' }
    return Invoke-GitHubApi POST $path $body -GitHub $GitHub
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
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Report,
        [Parameter(Mandatory)] [hashtable] $GitHub,
        [string[]] $Only = @()
    )

    if (-not $GitHub.Token) {
        throw '-Configure requires -GitHubToken or GITHUB_TOKEN.'
    }

    $owner = [string](Get-PropertyValue $Manifest 'owner')
    $missing = [Collections.Generic.HashSet[string]]::new(
        [string[]]@($Report.missing), [StringComparer]::OrdinalIgnoreCase)

    # -Only narrows configuring as it narrows creating: it was ignored here, so
    # creating two repositories reconfigured all of them (found 2026-09-24).
    [object[]] $declared = @(Get-PropertyValue $Manifest 'repositories' @())
    [string[]] $names = @($declared | ForEach-Object { [string](Get-PropertyValue $_ 'name') })
    foreach ($wanted in $Only) {
        if ($wanted -notin $names) {
            throw "-Only '$wanted' is not declared in the manifest; nothing is configured by guess."
        }
    }
    [object[]] $chosen = @($declared | Where-Object {
            $Only.Count -eq 0 -or [string](Get-PropertyValue $_ 'name') -in $Only })

    # GitHub refuses a description over 350 characters, and refused it after
    # every repository before it was configured. Every one is judged first.
    [string[]] $long = @($chosen | Where-Object {
            ([string](Get-PropertyValue $_ 'description')).Length -gt 350 } |
            ForEach-Object { [string](Get-PropertyValue $_ 'name') })
    if ($long.Count -gt 0) {
        throw ("REFUSED: GitHub takes a description of 350 characters or fewer, and " +
            "architecture.toml gives more for $($long -join ', ').")
    }

    foreach ($repository in $chosen) {
        $name = [string](Get-PropertyValue $repository 'name')

        # Nothing to configure on a repository that does not exist.
        if ($missing.Contains($name)) { continue }

        $wanted = Get-PropertyValue $repository 'github' ([pscustomobject]@{})
        $topics = @(ConvertTo-Array (Get-PropertyValue $wanted 'topics' @()) |
                ForEach-Object { ([string]$_).ToLowerInvariant() } |
                Where-Object { $_ -match '^[a-z0-9][a-z0-9-]{0,49}$' } |
                Select-Object -Unique)

        $settings = [ordered]@{
            description = [string](Get-PropertyValue $repository 'description')
            has_issues = [bool](Get-PropertyValue $wanted 'hasIssues' $true)
            has_projects = [bool](Get-PropertyValue $wanted 'hasProjects' $false)
            has_wiki = [bool](Get-PropertyValue $wanted 'hasWiki' $false)
        }

        if (-not $PSCmdlet.ShouldProcess("$owner/$name", 'Configure repository')) {
            $Report.operations.skipped++
            continue
        }

        Write-Step "Configuring $owner/$name"
        $null = Invoke-GitHubApi PATCH "/repos/$owner/$name" $settings -GitHub $GitHub

        # Topics are their own endpoint and replace wholesale, which is what
        # makes the manifest authoritative rather than additive.
        if ($topics.Count) {
            $named = [ordered]@{ names = $topics }
            $null = Invoke-GitHubApi PUT "/repos/$owner/$name/topics" $named -GitHub $GitHub
        }

        $Report.operations.configured++
    }
}

function Invoke-CreateRepositories {
    param(
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Report,
        [Parameter(Mandatory)] [hashtable] $GitHub,
        [switch] $IncludeReserved,
        [string[]] $Only = @()
    )

    if (-not $GitHub.Token) {
        throw '-Create requires -GitHubToken or GITHUB_TOKEN.'
    }

    $owner = [string](Get-PropertyValue $Manifest 'owner')
    $ownerInfo = Invoke-GitHubApi GET "/users/$owner" -GitHub $GitHub
    $ownerType = [string](Get-PropertyValue $ownerInfo 'type')
    if ($ownerType -notin @('User','Organization')) {
        throw "Unsupported GitHub owner type '$ownerType' for '$owner'."
    }

    if ($ownerType -eq 'User') {
        $currentUser = Invoke-GitHubApi GET '/user' -GitHub $GitHub
        $currentLogin = [string](Get-PropertyValue $currentUser 'login')
        if ($currentLogin -ine $owner) {
            throw ("Authenticated GitHub user '$currentLogin' cannot create repositories " +
                "for '$owner'.")
        }
    }

    [hashtable] $template = Get-XmipTemplate -Manifest $Manifest

    if ($template.Count -eq 0) {
        [string] $warning = 'No crate.template in the manifest. Repositories will be created ' +
            'blank, with no licence, workflow or layout.'

        Write-Warning $warning
    }

    # Every declared template, checked before anything is created. One that
    # has been renamed or unmarked fails here rather than on the first
    # repository that needed it.
    foreach ($language in @($template.Keys | Sort-Object)) {
        [string] $name = $template[$language]
        $templateInfo = Invoke-GitHubApi GET "/repos/$name" -GitHub $GitHub

        if (-not [bool](Get-PropertyValue $templateInfo 'is_template' $false)) {
            [string] $message = "'$name' is not marked as a template repository. Enable " +
                'Settings, Template repository on it, or remove it from crate.template.'

            throw $message
        }

        Write-Step "Template for $language`: $name"
    }

    $desired = @{}
    foreach ($repository in @(Get-PropertyValue $Manifest 'repositories' @())) {
        $desired[[string](Get-PropertyValue $repository 'name')] = $repository
    }

    if ($Only.Count -gt 0) {
        foreach ($wanted in $Only) {
            if (-not $desired.ContainsKey($wanted)) {
                throw "-Only '$wanted' is not declared in the manifest; " +
                    'nothing is created by guess.'
            }
        }
    }

    foreach ($name in @($Report.missing)) {
        if ($Only.Count -gt 0 -and $Only -notcontains $name) {
            $Report.operations.skipped++
            continue
        }

        $repository = $desired[$name]
        if ($null -eq $repository) { throw "Missing repository definition for '$name'." }

        $maturity = [string](Get-PropertyValue $repository 'maturity' 'reserved')
        if ($maturity -eq 'reserved' -and -not $IncludeReserved) {
            Write-Warning "SKIPPED RESERVED: $name"
            $Report.operations.skipped++
            continue
        }

        $existing = Test-GitHubRepositoryExists -Owner $owner -Name $name -GitHub $GitHub
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
        [hashtable] $creation = @{
            Repository = $repository
            Owner      = $owner
            OwnerType  = $ownerType
            Template   = $template
        }

        $created = New-XmipGitHubRepository @creation -GitHub $GitHub
        $createdName = [string](Get-PropertyValue $created 'name')
        if ($createdName -ine $name) {
            throw "GitHub returned repository '$createdName' while creating '$name'."
        }

        $verification = Test-GitHubRepositoryExists -Owner $owner -Name $name -GitHub $GitHub
        if (-not $verification.Exists) {
            throw "Repository '$owner/$name' was not visible after creation."
        }

        $Report.operations.created++
        $Report.actualCount++
        $Report.missing = @($Report.missing | Where-Object { $_ -ine $name })
    }
}
