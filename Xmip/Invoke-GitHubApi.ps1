#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Talking to GitHub for Sync-XmipEstate: the REST calls, the paging and what exists.

.DESCRIPTION
    Nested inside Sync-XmipEstate until 2026-09-22, which made that one function
    719 lines against the 400 the estate allows a file, and let every helper
    read the GitHub token and address out of its scope unseen. Lifted when the
    owner asked for the estate to be consolidated; each now takes the
    connection it uses as a parameter, -GitHub.

    Style: doc/governance/powershell-style.md
#>

function Assert-Command([string] $Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}

function Get-GitHubHeaders {
    param([Parameter(Mandatory)] [hashtable] $GitHub)

    $headers = @{
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'Xmip-Architecture-Reconciler'
    }
    if ($GitHub.Token) { $headers.Authorization = "Bearer $($GitHub.Token)" }
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
        [ref] $StatusCode,
        [Parameter(Mandatory)] [hashtable] $GitHub
    )

    $uri = if ($Path -match '^https?://') {
        $Path
    }
    else {
        "$($GitHub.BaseUri.TrimEnd('/'))/$($Path.TrimStart('/'))"
    }

    $parameters = @{
        Method = $Method
        Uri = $uri
        Headers = Get-GitHubHeaders -GitHub $GitHub
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
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [hashtable] $GitHub
    )

    $status = 0
    [hashtable] $asking = @{ StatusCode = ([ref] $status); GitHub = $GitHub }
    $repository = Invoke-GitHubApi GET "/repos/$Owner/$Name" @asking

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
    param([Parameter(Mandatory)] [string] $Owner, [Parameter(Mandatory)] [int] $Page,
    [Parameter(Mandatory)] [hashtable] $GitHub)

    [string] $path = if ($GitHub.Token) {
        "/user/repos?per_page=100&affiliation=owner&page=$Page"
    }
    else {
        "/users/$Owner/repos?per_page=100&page=$Page"
    }

    return @(Invoke-GitHubApi GET $path -GitHub $GitHub)
}

function Get-ActualRepositories {
    # One request per declared repository was 336 requests and about three
    # minutes before anything appeared, which made every command feel dead.
    # Listing pages at 100, so the same answer costs four.
    param([Parameter(Mandatory)] $Manifest,
    [Parameter(Mandatory)] [hashtable] $GitHub)

    # Everything the owner has, not only what the manifest already knows.
    # Filtering to declared names here made an undeclared repository
    # invisible by construction, which is why 'unexpected' could never be
    # anything but zero — and a repository left behind under an old name is
    # exactly an undeclared repository.
    $owner = [string](Get-PropertyValue $Manifest 'owner')
    $actual = [Collections.Generic.List[object]]::new()
    [int] $page = 1

    while ($true) {
        [object[]] $batch = @(Get-RepositoryPage -Owner $owner -Page $page -GitHub $GitHub)
        $actual.AddRange($batch)

        if (100 -gt $batch.Count) {
            break
        }

        $page++
    }

    return @($actual.ToArray())
}
