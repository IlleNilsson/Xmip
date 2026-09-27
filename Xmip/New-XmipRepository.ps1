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


function New-XmipGitHubRepository {
    param(
        [Parameter(Mandatory = $true)]
        $Repository,

        [Parameter(Mandatory = $true)]
        [string] $Owner,

        [Parameter(Mandatory = $true)]
        [ValidateSet('User', 'Organization')]
        [string] $OwnerType,

        [Parameter(Mandatory = $false)]
        [hashtable] $Template = @{},

        [Parameter(Mandatory = $true)]
        [hashtable] $GitHub
    )

    $name = [string](Get-XmipPropertyValue -Object $Repository -Name 'name')
    $description = [string](Get-XmipPropertyValue -Object $Repository -Name 'description')
    $wanted = (
        Get-XmipPropertyValue -Object $Repository -Name 'github' -Default @{}
    )
    $visibility = [string](
        Get-XmipPropertyValue -Object $wanted -Name 'visibility' -Default 'public'
    )
    if ($visibility -notin @('public','private','internal')) {
        throw "Unsupported GitHub visibility '$visibility' for '$name'."
    }
    if ($OwnerType -eq 'User' -and $visibility -eq 'internal') {
        throw "Visibility 'internal' is not valid for user-owned repository '$name'."
    }

    $settings = [ordered]@{
        has_issues = [bool](Get-XmipPropertyValue -Object $wanted -Name 'hasIssues' -Default $true)
        has_projects = [bool](
            Get-XmipPropertyValue -Object $wanted -Name 'hasProjects' -Default $false
        )
        has_wiki = [bool](Get-XmipPropertyValue -Object $wanted -Name 'hasWiki' -Default $false)
    }

    # One template per language. A module generated from the wrong one
    # arrives holding a Cargo.toml it will never build. ADR-0014 clause 14.
    $primaryCrate = (
        Get-XmipPropertyValue -Object $Repository -Name 'primaryCrate' -Default @{}
    )
    $language = [string](
        Get-XmipPropertyValue -Object $primaryCrate -Name 'language' -Default 'rust'
    )
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

        [hashtable] $generate = @{
            Path   = "/repos/$chosen/generate"
            Body   = $body
            GitHub = $GitHub
        }
        $created = Invoke-XmipGitHubApi -Method POST @generate

        # generate takes none of the feature switches, so they follow.
        [hashtable] $switches = @{
            Path   = "/repos/$Owner/$name"
            Body   = $settings
            GitHub = $GitHub
        }
        $null = Invoke-XmipGitHubApi -Method PATCH @switches
        return $created
    }

    $body = [ordered]@{
        name = $name
        description = $description
        private = ($visibility -eq 'private')
        auto_init = [bool](
            Get-XmipPropertyValue -Object $wanted -Name 'autoInitialize' -Default $true
        )
    }
    foreach ($key in $settings.Keys) { $body[$key] = $settings[$key] }
    if ($OwnerType -eq 'Organization') { $body.visibility = $visibility }

    $path = if ($OwnerType -eq 'Organization') { "/orgs/$Owner/repos" } else { '/user/repos' }
    return Invoke-XmipGitHubApi -Method POST -Path $path -Body $body -GitHub $GitHub
}

function Set-XmipRepository {
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
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Report,

        [Parameter(Mandatory = $true)]
        [hashtable] $GitHub,

        [Parameter(Mandatory = $false)]
        [string[]] $Only = @()
    )

    if (-not $GitHub.Token) {
        throw '-Configure requires -GitHubToken or GITHUB_TOKEN.'
    }

    $owner = [string](Get-XmipPropertyValue -Object $Manifest -Name 'owner')
    $missing = [Collections.Generic.HashSet[string]]::new(
        [string[]]@($Report.missing), [StringComparer]::OrdinalIgnoreCase)

    # -Only narrows configuring as it narrows creating: it was ignored here, so
    # creating two repositories reconfigured all of them (found 2026-09-24).
    [object[]] $declared = @(
        Get-XmipPropertyValue -Object $Manifest -Name 'repositories' -Default @()
    )
    [string[]] $names = @(
        $declared | ForEach-Object { [string](Get-XmipPropertyValue -Object $_ -Name 'name') }
    )
    foreach ($wanted in $Only) {
        if ($wanted -notin $names) {
            throw "-Only '$wanted' is not declared in the manifest; nothing is configured by guess."
        }
    }
    [object[]] $chosen = @($declared | Where-Object {
            $Only.Count -eq 0 -or [string](Get-XmipPropertyValue -Object $_ -Name 'name') -in $Only
        })

    # GitHub refuses a description over 350 characters, and refused it after
    # every repository before it was configured. Every one is judged first.
    [string[]] $long = @($chosen | Where-Object {
            ([string](Get-XmipPropertyValue -Object $_ -Name 'description')).Length -gt 350 } |
            ForEach-Object { [string](Get-XmipPropertyValue -Object $_ -Name 'name') })
    if ($long.Count -gt 0) {
        throw ("REFUSED: GitHub takes a description of 350 characters or fewer, and " +
            "architecture.toml gives more for $($long -join ', ').")
    }

    foreach ($repository in $chosen) {
        $name = [string](Get-XmipPropertyValue -Object $repository -Name 'name')

        # Nothing to configure on a repository that does not exist.
        if ($missing.Contains($name)) { continue }

        $wanted = (
            Get-XmipPropertyValue -Object $repository -Name 'github' -Default @{}
        )
        $declaredTopics = Get-XmipPropertyValue -Object $wanted -Name 'topics' -Default @()
        $topics = @(ConvertTo-XmipArray -Value $declaredTopics |
                ForEach-Object { ([string]$_).ToLowerInvariant() } |
                Where-Object { $_ -match '^[a-z0-9][a-z0-9-]{0,49}$' } |
                Select-Object -Unique)

        $settings = [ordered]@{
            description = [string](Get-XmipPropertyValue -Object $repository -Name 'description')
            has_issues = [bool](
                Get-XmipPropertyValue -Object $wanted -Name 'hasIssues' -Default $true
            )
            has_projects = [bool](
                Get-XmipPropertyValue -Object $wanted -Name 'hasProjects' -Default $false
            )
            has_wiki = [bool](Get-XmipPropertyValue -Object $wanted -Name 'hasWiki' -Default $false)
        }

        if (-not $PSCmdlet.ShouldProcess("$owner/$name", 'Configure repository')) {
            $Report.operations.skipped++
            continue
        }

        Write-XmipStep -Message "Configuring $owner/$name"
        [hashtable] $configure = @{
            Path   = "/repos/$owner/$name"
            Body   = $settings
            GitHub = $GitHub
        }
        $null = Invoke-XmipGitHubApi -Method PATCH @configure

        # Topics are their own endpoint and replace wholesale, which is what
        # makes the manifest authoritative rather than additive.
        if ($topics.Count) {
            $named = [ordered]@{ names = $topics }
            [hashtable] $replace = @{
                Path   = "/repos/$owner/$name/topics"
                Body   = $named
                GitHub = $GitHub
            }
            $null = Invoke-XmipGitHubApi -Method PUT @replace
        }

        $Report.operations.configured++
    }
}

function New-XmipRepository {
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Report,

        [Parameter(Mandatory = $true)]
        [hashtable] $GitHub,

        [Parameter(Mandatory = $false)]
        [switch] $IncludeReserved,

        [Parameter(Mandatory = $false)]
        [string[]] $Only = @()
    )

    if (-not $GitHub.Token) {
        throw '-Create requires -GitHubToken or GITHUB_TOKEN.'
    }

    $owner = [string](Get-XmipPropertyValue -Object $Manifest -Name 'owner')
    $ownerInfo = Invoke-XmipGitHubApi -Method GET -Path "/users/$owner" -GitHub $GitHub
    $ownerType = [string](Get-XmipPropertyValue -Object $ownerInfo -Name 'type')
    if ($ownerType -notin @('User','Organization')) {
        throw "Unsupported GitHub owner type '$ownerType' for '$owner'."
    }

    if ($ownerType -eq 'User') {
        $currentUser = Invoke-XmipGitHubApi -Method GET -Path '/user' -GitHub $GitHub
        $currentLogin = [string](Get-XmipPropertyValue -Object $currentUser -Name 'login')
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
        $templateInfo = Invoke-XmipGitHubApi -Method GET -Path "/repos/$name" -GitHub $GitHub

        [bool] $isTemplate = [bool](
            Get-XmipPropertyValue -Object $templateInfo -Name 'is_template' -Default $false
        )

        if (-not $isTemplate) {
            [string] $message = "'$name' is not marked as a template repository. Enable " +
                'Settings, Template repository on it, or remove it from crate.template.'

            throw $message
        }

        Write-XmipStep -Message "Template for $language`: $name"
    }

    $desired = @{}
    [object[]] $declared = @(
        Get-XmipPropertyValue -Object $Manifest -Name 'repositories' -Default @()
    )

    foreach ($repository in $declared) {
        $desired[[string](Get-XmipPropertyValue -Object $repository -Name 'name')] = $repository
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

        $maturity = [string](
            Get-XmipPropertyValue -Object $repository -Name 'maturity' -Default 'reserved'
        )
        if ($maturity -eq 'reserved' -and -not $IncludeReserved) {
            Write-Warning "SKIPPED RESERVED: $name"
            $Report.operations.skipped++
            continue
        }

        $existing = Test-XmipGitHubRepository -Owner $owner -Name $name -GitHub $GitHub
        if ($existing.Exists) {
            Write-XmipStep -Message "Repository already exists: $owner/$name"
            $Report.actualCount++
            $Report.missing = @($Report.missing | Where-Object { $_ -ine $name })
            $Report.operations.skipped++
            continue
        }

        if (-not $PSCmdlet.ShouldProcess("$owner/$name", 'Create GitHub repository')) {
            $Report.operations.skipped++
            continue
        }

        Write-XmipStep -Message "Creating repository $owner/$name"
        [hashtable] $creation = @{
            Repository = $repository
            Owner      = $owner
            OwnerType  = $ownerType
            Template   = $template
        }

        $created = New-XmipGitHubRepository @creation -GitHub $GitHub
        $createdName = [string](Get-XmipPropertyValue -Object $created -Name 'name')
        if ($createdName -ine $name) {
            throw "GitHub returned repository '$createdName' while creating '$name'."
        }

        $verification = Test-XmipGitHubRepository -Owner $owner -Name $name -GitHub $GitHub
        if (-not $verification.Exists) {
            throw "Repository '$owner/$name' was not visible after creation."
        }

        $Report.operations.created++
        $Report.actualCount++
        $Report.missing = @($Report.missing | Where-Object { $_ -ine $name })
    }
}
