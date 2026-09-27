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

function Assert-XmipCommand {
    <#
        Throws when a command the caller needs is not on this machine.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}


function Get-XmipGitHubHeader {
    <#
        The headers every GitHub call sends, with the token when there is one.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $GitHub
    )

    [hashtable] $headers = @{
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'Xmip-Architecture-Reconciler'
    }

    if ($GitHub.Token) {
        $headers.Authorization = "Bearer $($GitHub.Token)"
    }

    return $headers
}


function Invoke-XmipGitHubApi {
    <#
        One GitHub REST call. -StatusCode asks for the status rather than an
        error: a 404 when probing for a repository is the answer, not a
        failure, and without it every absent repository threw and a first run
        wrote five hundred lines of TerminatingError for a result that was
        entirely expected.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string] $Method,

        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $false)]
        [object] $Body,

        [Parameter(Mandatory = $false)]
        [ref] $StatusCode,

        [Parameter(Mandatory = $true)]
        [hashtable] $GitHub
    )

    [string] $uri = if ($Path -match '^https?://') {
        $Path
    }
    else {
        "$($GitHub.BaseUri.TrimEnd('/'))/$($Path.TrimStart('/'))"
    }

    [hashtable] $parameters = @{
        Method      = $Method
        Uri         = $uri
        Headers     = Get-XmipGitHubHeader -GitHub $GitHub
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

    if ($StatusCode) {
        $StatusCode.Value = $responseStatus
    }

    return $response
}


function Test-XmipGitHubRepository {
    <#
        Whether GitHub has the repository, and what it says of it when it does.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Owner,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [hashtable] $GitHub
    )

    $status = 0
    [hashtable] $asking = @{ StatusCode = ([ref] $status); GitHub = $GitHub }
    $repository = Invoke-XmipGitHubApi -Method GET -Path "/repos/$Owner/$Name" @asking

    if ($status -eq 404) {
        return [pscustomobject]@{ Exists = $false; Repository = $null }
    }

    if ($status -ge 400) {
        [string] $detail = ''

        if ($repository.message) {
            $detail = ': {0}' -f $repository.message
        }

        throw "GitHub returned $status for /repos/$Owner/$Name$detail"
    }

    return [pscustomobject]@{ Exists = $true; Repository = $repository }
}


function Get-XmipGitHubRepositoryPage {
    <#
        One page of the owner's repositories. /user/repos with a token
        includes private repositories; the anonymous /users/<owner>/repos does
        not, so an unauthenticated run can report a private one as missing.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Owner,

        [Parameter(Mandatory = $true)]
        [int] $Page,

        [Parameter(Mandatory = $true)]
        [hashtable] $GitHub
    )

    [string] $path = if ($GitHub.Token) {
        "/user/repos?per_page=100&affiliation=owner&page=$Page"
    }
    else {
        "/users/$Owner/repos?per_page=100&page=$Page"
    }

    return @(Invoke-XmipGitHubApi -Method GET -Path $path -GitHub $GitHub)
}


function Get-XmipGitHubRepository {
    <#
        Every repository the owner has on GitHub, not only what the manifest
        already knows: filtering to declared names made an undeclared
        repository invisible by construction, and a repository left behind
        under an old name is exactly an undeclared one. Listed a hundred to a
        page; one request per declared repository was 336 requests and about
        three minutes before anything appeared.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [hashtable] $GitHub
    )

    [string] $owner = [string](Get-XmipPropertyValue -Object $Manifest -Name 'owner')
    $actual = [Collections.Generic.List[object]]::new()
    [int] $page = 1

    while ($true) {
        [hashtable] $asked = @{ Owner = $owner; Page = $page; GitHub = $GitHub }
        [object[]] $batch = @(Get-XmipGitHubRepositoryPage @asked)
        $actual.AddRange($batch)

        if (100 -gt $batch.Count) {
            break
        }

        $page++
    }

    return @($actual.ToArray())
}
