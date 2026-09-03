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

    Depth two mounts under Xmip, grouped by architectural domain, because that
    layout exists for human navigation:

        xmip-core-transport   ->  modules/capabilities/transport
        xmip-core-journey     ->  modules/foundation/journey

    Depth three mounts inside its own parent capability, ungrouped, because at
    that level the parent is the grouping:

        xmip-core-transport-kafka  ->  modules/kafka

    The name is the TOML tree path with dots as hyphens, so the mount name is
    the last segment and the owner is the name minus that segment.
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
    [string] $owner = Get-XmipDeclaredOwner -Name $name -Declared $Declared
    [string] $leaf = $name

    if ('' -ne $owner) {
        $leaf = $name.Substring($owner.Length + 1)
    }
    elseif ($name.StartsWith('xmip-', [StringComparison]::OrdinalIgnoreCase)) {
        $leaf = $name.Substring(5)
    }

    # xmip-core is both a repository and the prefix every module carries, so a
    # module resolves to it. Modules mount under the estate root regardless —
    # ADR-0016 shows Xmip pinning modules/transport directly.
    if (('' -eq $owner) -or ($owner -ieq 'xmip-core')) {
        [string] $domain = [string](Get-PropertyValue $Repository 'architecturalDomain' 'Capabilities')
        return [pscustomobject]@{ Owner = ''; Mount = "modules/$($domain.ToLowerInvariant())/$leaf" }
    }

    return [pscustomobject]@{ Owner = $owner; Mount = "modules/$leaf" }
}

<#
    .SYNOPSIS
    The longest declared repository name that this one sits beneath, or ''.

    .DESCRIPTION
    Splitting a name on '-' does not work: a segment may itself contain
    hyphens, so xmip-core-transport-can-bus splits into five and yields a leaf
    of 'bus' owned by 'xmip-core-transport-can'. Both are wrong and neither
    exists. The manifest is its own index — the owner is the longest declared
    name this one is prefixed by.
#>
function Get-XmipDeclaredOwner {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Declared
    )

    [string] $owner = ''

    foreach ($candidate in $Declared) {
        if (-not $Name.StartsWith("$candidate-", [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ($candidate.Length -gt $owner.Length) {
            $owner = $candidate
        }
    }

    return $owner
}

<#
    .SYNOPSIS
    The owner/name of the repository new crates are generated from, or ''.

    .DESCRIPTION
    crate.template in schema 2.0, cratePolicy.template in schema 1.
#>
function Get-XmipTemplate {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    $crate = Get-TomlValue $Manifest 'crate' $null
    $declared = Get-TomlValue $crate 'template' $null

    # A string in schema 2.0 before 2026-08-27, and in cratePolicy in schema 1.
    # Both meant "the Rust template", because there was only one.
    if ($declared -is [string]) {
        return @{ rust = $declared }
    }

    if ($null -eq $declared) {
        [string] $legacy = [string](
            Get-PropertyValue (Get-PropertyValue $Manifest 'cratePolicy') 'template' ''
        )

        if ([string]::IsNullOrWhiteSpace($legacy)) {
            return @{}
        }

        return @{ rust = $legacy }
    }

    $templates = @{}

    foreach ($language in (Get-TomlKey -Node $declared)) {
        $templates[$language] = [string](Get-TomlValue $declared $language '')
    }

    return $templates
}

<#
    .SYNOPSIS
    Repositories the manifest says were retired.

    .DESCRIPTION
    Archived rather than deleted, so they are still on GitHub and would
    otherwise report as drift for as long as they exist. A warning that is
    always there is a warning nobody reads.
#>
function Get-XmipRetiredName {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    return @(
        @(Get-TomlValue $Manifest 'retired' @()) |
            ForEach-Object { [string](Get-TomlValue $_ 'name' '') } |
            Where-Object { $_ }
    )
}

<#
    .SYNOPSIS
    Repositories in the Xmip namespace that the manifest does not declare.

    .DESCRIPTION
    Only names beginning xmip-. The owner's other repositories are none of the
    estate's business, and reporting them would make the number noise rather
    than a finding.

    An unexpected repository is usually one of two things: something created
    deliberately and not yet declared, or something left behind under a name
    the manifest has since changed. The responses are opposites — declare it,
    or rename it — so this reports and does not guess.
#>
function Get-XmipUnexpectedName {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Actual,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Declared,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $Template = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $Retired = @()
    )

    $declaredSet = [System.Collections.Generic.HashSet[string]]::new(
        $Declared, [StringComparer]::OrdinalIgnoreCase)

    # The template repositories are referenced by the manifest — crate.template
    # — but are not repositories it declares, so they reported as unexpected on
    # the first run that could report anything. They are not stray; they are
    # what -Create generates from.
    #
    # Plural since 2026-08-27: one per language, and the estate has two.
    foreach ($name in $Template) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            [void] $declaredSet.Add(($name -split '/')[-1])
        }
    }

    # Retired repositories are archived rather than deleted, so they stay
    # visible. Reporting them forever would train a reader to ignore the
    # warning that also reports real drift.
    foreach ($name in $Retired) {
        [void] $declaredSet.Add($name)
    }

    return @(
        $Actual |
            Where-Object { $_ -like 'xmip-*' -and -not $declaredSet.Contains($_) } |
            Sort-Object
    )
}

<#
    .SYNOPSIS
    A case-insensitive set of the names on a collection of manifest entries.

    .DESCRIPTION
    Get-ActualRepositories returns GitHub repository objects, not names.
    Declaring the caller's parameter [string[]] coerced them to type names and
    matched nothing, which reported every repository as waiting on creation.
#>
function Get-XmipNameSet {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.HashSet[string]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Entries
    )

    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in @(ConvertTo-Array $Entries)) {
        [void] $names.Add([string](Get-PropertyValue $entry 'name'))
    }

    return $names
}

<#
    .SYNOPSIS
    The commit each submodule is pinned at, by repository name.

    .DESCRIPTION
    git ls-tree reads the gitlink, which is the commit the superproject pins —
    not whatever the working copy happens to be sitting on.

    This is what lets a Cargo git dependency be derived rather than maintained.
    The estate is otherwise wired twice, by .gitmodules and by hand-written rev
    values, and the two drift silently: xmip-core has a new commit today and
    every module still builds against the old SHA.
#>
function Get-XmipPinnedCommit {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [hashtable] $MountOf
    )

    [hashtable] $pinned = @{}

    foreach ($name in $MountOf.Keys) {
        [string] $mount = [string] $MountOf[$name]
        [string[]] $arguments = @('ls-tree', 'HEAD', '--', $mount)
        [string[]] $output = @(Invoke-Native -FilePath 'git' -Arguments $arguments -At $Root -CaptureOutput)

        # 160000 commit <sha>\t<path>
        if (0 -lt $output.Count -and $output[0] -match '^\d+\s+commit\s+([0-9a-f]{40})') {
            $pinned[$name] = $Matches[1]
        }
    }

    return $pinned
}

<#
    .SYNOPSIS
    Where each repository is currently mounted, by repository name.

    .DESCRIPTION
    Reads .gitmodules. A repository whose architecturalDomain changes gets a new
    computed mount path, and without this the old mount is invisible: -Compose
    only ever added, so a moved module stayed where it was until someone ran
    git mv by hand.
#>
function Get-XmipMountedPath {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root
    )

    [hashtable] $mounted = @{}
    [string] $file = Join-Path $Root '.gitmodules'

    if (-not (Test-Path -LiteralPath $file)) {
        return $mounted
    }

    [string] $path = ''

    foreach ($line in (Get-Content -LiteralPath $file)) {
        if ($line -match '^\s*path\s*=\s*(.+?)\s*$') {
            $path = $Matches[1]
            continue
        }

        if ($line -match '^\s*url\s*=\s*.+/([^/]+?)(\.git)?\s*$') {
            $mounted[$Matches[1]] = $path
        }
    }

    return $mounted
}

<#
    .SYNOPSIS
    What can be composed now, what is mounted, and what is waiting.

    .DESCRIPTION
    Pure: reads the manifest and the disk, decides nothing about git. Returns
    ready as objects carrying Name and Mount, plus counts for the rest.

    Only repositories that exist remotely can be pinned, and a depth-three
    repository needs its parent composed first — repository-model.md section 7.
#>
function Get-XmipComposePlan {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Actual,

        [Parameter(Mandatory = $true)]
        [string] $Root
    )

    $exists = Get-XmipNameSet -Entries $Actual
    [string[]] $declared = @(
        Get-PropertyValue $Manifest 'repositories' @() |
            ForEach-Object { [string](Get-PropertyValue $_ 'name') }
    )

    $ready = [System.Collections.Generic.List[object]]::new()
    $misplaced = [System.Collections.Generic.List[object]]::new()
    [hashtable] $where = Get-XmipMountedPath -Root $Root
    [int] $mounted = 0
    [int] $waiting = 0
    [int] $retiredCount = 0

    foreach ($repository in @(Get-PropertyValue $Manifest 'repositories' @())) {
        [string] $name = [string](Get-PropertyValue $repository 'name')
        [string] $maturity = [string](Get-PropertyValue $repository 'maturity' 'reserved')

        # A deprecated or retired repository still exists on GitHub, so without
        # this it gets mounted straight back after someone removes it.
        if ($maturity -in 'deprecated', 'retired') {
            $retiredCount++
            continue
        }

        $mount = Get-XmipMountPath -Repository $repository -Declared $declared

        # Waiting: not created yet, or owned by a module that must itself be
        # composed first. Level two follows level one.
        if (-not $exists.Contains($name) -or ('' -ne $mount.Owner)) {
            $waiting++
            continue
        }

        [string] $current = [string] $where[$name]

        if ($current -eq $mount.Mount) {
            $mounted++
            continue
        }

        # Mounted, but not where the manifest now says. Move rather than add:
        # adding would leave two mounts of one repository.
        if (-not [string]::IsNullOrEmpty($current)) {
            $misplaced.Add([pscustomobject]@{ Name = $name; From = $current; Mount = $mount.Mount })
            continue
        }

        $ready.Add([pscustomobject]@{ Name = $name; Mount = $mount.Mount })
    }

    return @{
        ready     = @($ready.ToArray())
        misplaced = @($misplaced.ToArray())
        mounted   = $mounted
        waiting   = $waiting
        retired   = $retiredCount
    }
}

<#
    .SYNOPSIS
    Splits missing repositories into actionable drift and expected absence.

    .DESCRIPTION
    A reserved repository that does not exist is not drift — repository-model.md
    section 3 says the manifest is the design and creation follows need.
    Reporting all of them printed 293 warnings to surface one action.
#>
function Split-XmipDrift {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Missing
    )

    [hashtable] $maturityOf = @{}

    foreach ($repository in @(Get-PropertyValue $Manifest 'repositories' @())) {
        [string] $name = [string](Get-PropertyValue $repository 'name')
        $maturityOf[$name] = [string](Get-PropertyValue $repository 'maturity' 'reserved')
    }

    $actionable = [System.Collections.Generic.List[object]]::new()
    $expected = [System.Collections.Generic.List[string]]::new()

    foreach ($name in $Missing) {
        [string] $maturity = [string] $maturityOf[$name]

        if ($maturity -eq 'reserved') {
            $expected.Add($name)
            continue
        }

        $actionable.Add([pscustomobject]@{ Name = $name; Maturity = $maturity })
    }

    return @{ actionable = @($actionable.ToArray()); expected = @($expected.ToArray()) }
}

<#
    .SYNOPSIS
    What a module's Cargo.toml should say, against what it says.

    .DESCRIPTION
    Two things are reconciled, both derived rather than maintained.

    **The Cargo package name is the repository name.** architecture.toml sets
    primaryCrateMatchesRepository. A dependency may use a shorter local key,
    such as `xmip-message`, while its package remains `xmip-core-message`.

    **A dependency rev is the commit the superproject pins.** Otherwise the
    estate is wired twice and the two wirings drift without anyone noticing.

    Returns one finding per line that needs changing. Nothing is written here.
#>
function Get-XmipCrateFinding {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [hashtable] $MountOf,

        [Parameter(Mandatory = $true)]
        [hashtable] $PinnedAt
    )

    foreach ($name in ($MountOf.Keys | Sort-Object)) {
        [string] $file = Join-Path $Root (Join-Path $MountOf[$name] 'Cargo.toml')

        if (-not (Test-Path -LiteralPath $file)) {
            continue
        }

        [string[]] $lines = @(Get-Content -LiteralPath $file)

        for ([int] $index = 0; $index -lt $lines.Count; $index++) {
            $finding = Test-XmipCrateLine -Line $lines[$index] -PinnedAt $PinnedAt

            if ($null -eq $finding) {
                continue
            }

            $finding | Add-Member -NotePropertyName File -NotePropertyValue $file
            $finding | Add-Member -NotePropertyName Line -NotePropertyValue ($index + 1)
            $finding | Add-Member -NotePropertyName Module -NotePropertyValue $name
            $finding
        }
    }
}

<#
    .SYNOPSIS
    Whether one Cargo.toml line disagrees with the estate, and what it should be.
#>
function Test-XmipCrateLine {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Line,

        [Parameter(Mandatory = $true)]
        [hashtable] $PinnedAt
    )

    # Cargo package identity is validated against the repository by the estate
    # manifest and template. A shorter dependency key is only a local alias; the
    # package remains, for example, xmip-core-message.

    # xmip-core = { git = "...", rev = "..." }
    if ($Line -notmatch '^\s*(xmip[\w-]*)\s*=\s*\{.*\brev\s*=\s*"([0-9a-f]+)"') {
        return $null
    }

    [string] $dependency = $Matches[1]
    [string] $rev = $Matches[2]
    [string] $should = [string] $PinnedAt[$dependency]

    if ([string]::IsNullOrEmpty($should) -or $rev -ceq $should) {
        return $null
    }

    return [pscustomobject]@{
        Rule = 'DependencyRev'
        Was  = "$dependency $($rev.Substring(0, 7))"
        Is   = "$dependency $($should.Substring(0, 7))"
        New  = $Line -replace '\brev\s*=\s*"[0-9a-f]+"', "rev = `"$should`""
    }
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
            [string] $detail = ''

            if ($repository.message) {
                $detail = ': {0}' -f $repository.message
            }

            throw "GitHub returned $status for /repos/$Owner/$Name$detail"
        }
        return [pscustomobject]@{ Exists = $true; Repository = $repository }
    }

    function Get-RepositoryPage {
        # /user/repos with a token includes private repositories. The anonymous
        # /users/<owner>/repos does not, so an unauthenticated run can report a
        # private repository as missing.
        param([Parameter(Mandatory)] [string] $Owner, [Parameter(Mandatory)] [int] $Page)

        [string] $path = if ($GitHubToken) {
            "/user/repos?per_page=100&affiliation=owner&page=$Page"
        }
        else {
            "/users/$Owner/repos?per_page=100&page=$Page"
        }

        return @(Invoke-GitHubApi GET $path)
    }

    function Get-ActualRepositories {
        # One request per declared repository was 336 requests and about three
        # minutes before anything appeared, which made every command feel dead.
        # Listing pages at 100, so the same answer costs four.
        param([Parameter(Mandatory)] $Manifest)

        # Everything the owner has, not only what the manifest already knows.
        # Filtering to declared names here made an undeclared repository
        # invisible by construction, which is why 'unexpected' could never be
        # anything but zero — and a repository left behind under an old name is
        # exactly an undeclared repository.
        $owner = [string](Get-PropertyValue $Manifest 'owner')
        $actual = [Collections.Generic.List[object]]::new()
        [int] $page = 1

        while ($true) {
            [object[]] $batch = @(Get-RepositoryPage -Owner $owner -Page $page)
            $actual.AddRange($batch)

            if (100 -gt $batch.Count) {
                break
            }

            $page++
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
            architectureVersion = [string](Get-PropertyValue $Manifest 'architectureVersion' 'unversioned')
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
            [hashtable] $Template = @{}
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

            $created = Invoke-GitHubApi POST "/repos/$chosen/generate" $body

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
            $templateInfo = Invoke-GitHubApi GET "/repos/$name"

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
            [hashtable] $creation = @{
                Repository = $repository
                Owner      = $owner
                OwnerType  = $ownerType
                Template   = $template
            }

            $created = New-XmipGitHubRepository @creation
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














    function Invoke-Compose {
        # Short on purpose: the plan is computed at file scope, so this only
        # performs it. ShouldProcess is why it cannot move out with the rest.
        [CmdletBinding()]
        param(
            [Parameter(Mandatory = $true)]
            $Manifest,

            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [object[]] $Actual
        )

        Assert-Command 'git'

        [string] $root = Get-XmipRepositoryRoot
        [string] $owner = [string](Get-PropertyValue $Manifest 'owner')
        $plan = Get-XmipComposePlan -Manifest $Manifest -Actual $Actual -Root $root
        [int] $added = 0

        foreach ($item in @($plan.ready)) {
            if (-not $PSCmdlet.ShouldProcess("$($item.Mount) -> $($item.Name)", 'Add submodule')) {
                continue
            }

            [string] $url = "https://github.com/$owner/$($item.Name).git"
            [string[]] $arguments = @('submodule', 'add', '--', $url, $item.Mount)

            Invoke-Native -FilePath 'git' -Arguments $arguments -At $root | Out-Null
            Write-Host "COMPOSED: $($item.Mount)"
            $added++
        }

        [int] $moved = 0

        foreach ($item in @($plan.misplaced)) {
            [string] $what = '{0}: {1} -> {2}' -f $item.Name, $item.From, $item.Mount

            if (-not $PSCmdlet.ShouldProcess($what, 'Move submodule')) {
                continue
            }

            Invoke-Native -FilePath 'git' -Arguments @('mv', $item.From, $item.Mount) -At $root |
                Out-Null

            Write-Host "MOVED: $what"
            $moved++
        }

        [string] $summary =
            'Compose: {0} added, {1} moved, {2} already mounted, {3} waiting, {4} deprecated' -f
            $added, $moved, $plan.mounted, $plan.waiting, $plan.retired

        Write-Step $summary

        if (0 -lt $added) {
            Write-Step 'Review .gitmodules, then commit. Nothing was pushed.'
        }
    }

    function Invoke-Cargo {
        # Rewrites nothing that is already right, so it is safe to run twice.
        [CmdletBinding()]
        param()

        Assert-Command 'git'

        [string] $root = Get-XmipRepositoryRoot
        [hashtable] $mountOf = Get-XmipMountedPath -Root $root
        [hashtable] $pinnedAt = Get-XmipPinnedCommit -Root $root -MountOf $mountOf

        [hashtable] $edits = @{}
        [int] $revs = 0

        foreach ($finding in @(Get-XmipCrateFinding -Root $root -MountOf $mountOf -PinnedAt $pinnedAt)) {
            Write-Host ('  {0,-28} {1} -> {2}' -f $finding.Module, $finding.Was, $finding.Is)

            if (-not $edits.ContainsKey($finding.File)) {
                $edits[$finding.File] = @{}
            }

            $edits[$finding.File][$finding.Line] = $finding.New

            $revs++
        }

        foreach ($file in $edits.Keys) {
            if (-not $PSCmdlet.ShouldProcess($file, 'Rewrite Cargo.toml')) {
                continue
            }

            [string[]] $lines = @(Get-Content -LiteralPath $file)

            foreach ($line in $edits[$file].Keys) {
                $lines[$line - 1] = $edits[$file][$line]
            }

            Set-Content -LiteralPath $file -Value $lines -Encoding utf8NoBOM
        }

        [int] $rooted = 0

        foreach ($name in $mountOf.Keys) {
            [string] $file = Join-Path $root (Join-Path $mountOf[$name] 'Cargo.toml')

            if (-not (Test-Path -LiteralPath $file)) {
                continue
            }

            [string] $text = Get-Content -LiteralPath $file -Raw

            if ($text -match '(?m)^\s*\[workspace\]') {
                continue
            }

            if (-not $PSCmdlet.ShouldProcess($name, 'Make its own workspace root')) {
                continue
            }

            # Cargo walks up from a package looking for a workspace, finds
            # Xmip/Cargo.toml and refuses to build. exclude in the parent is not
            # enough and does not travel: a standalone clone has no parent to
            # read it from. An empty [workspace] here stops the walk.
            [string[]] $header = @(
                '# Its own workspace root, so this repository builds on its own.',
                '[workspace]',
                ''
            )

            [hashtable] $write = @{
                LiteralPath = $file
                Value       = $header + @(Get-Content -LiteralPath $file)
                Encoding    = 'utf8NoBOM'
            }

            Set-Content @write

            Write-Host "  ROOTED: $name"
            $rooted++
        }

        if (0 -lt $rooted) {
            Write-Step "Cargo: $rooted modules made their own workspace root"
        }

        Write-Step "Cargo: $revs dependency revs in $($edits.Count) files"

        if (0 -lt $edits.Count) {
            Write-Step 'Each module is its own repository. Commit and push them individually.'
        }
    }

    # No operation switch means report only. That is the safe default and it
    # needs no ceremony to reach.
    $operating = $Create -or $Configure -or $Compose -or $Cargo

    $manifest = Get-XmipManifest $ManifestPath
    Test-XmipManifest $manifest
    $actual = @(Get-ActualRepositories -Manifest $manifest)
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

    if ($Create) { Invoke-CreateRepositories -Manifest $manifest -Report $drift }
    if ($Configure) { Invoke-ConfigureRepositories -Manifest $manifest -Report $drift }
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
