#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What a landing lands on, and the one push that lands it: main, and a
    push that is checked to have reached origin's main.

.DESCRIPTION
    A commit made on another branch is not landed by pushing main, and git
    says "up to date" when the local main already is: a landing has to know
    which branch it commits on and see origin's main move to its commit.

    Style: doc/governance/powershell-style.md
#>


# The branch every repository of the estate lands on.
[string] $script:XmipMainBranch = 'main'


function Assert-XmipLandable {
    <#
        .SYNOPSIS
            Refuses a repository that is on a branch other than main. A
            detached head, as a submodule usually is, lands on main.

        .PARAMETER At
            The repository's working tree.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $At
    )

    [string[]] $asked = @('symbolic-ref', '--quiet', '--short', 'HEAD')

    if (-not (Invoke-XmipGit -At $At -Arguments $asked -Test)) {
        return
    }

    [string] $branch = (@(Invoke-XmipGit -At $At -Arguments $asked) -join '').Trim()

    if ($branch -ne $script:XmipMainBranch) {
        throw ("REFUSED: $At is on the branch $branch, and a landing commits and pushes " +
            "$script:XmipMainBranch. Switch it to $script:XmipMainBranch, or merge the " +
            'branch first; nothing was verified or landed.')
    }
}


function Push-XmipMain {
    <#
        .SYNOPSIS
            Pushes the commit at HEAD to origin's main, and fails unless
            origin's main is that commit afterwards.

        .PARAMETER At
            The repository's working tree.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $At
    )

    [string] $ref = "refs/heads/$script:XmipMainBranch"
    Invoke-XmipGit -At $At -Arguments @('push', 'origin', "HEAD:$ref", '--quiet') | Out-Null

    [string] $local = (@(Invoke-XmipGit -At $At -Arguments @('rev-parse', 'HEAD')) -join '').Trim()
    [string] $said = (@(Invoke-XmipGit -At $At -Arguments @('ls-remote', 'origin', $ref)) -join '')
    [string] $remote = ($said -split '\s+')[0]

    if ($remote -ne $local) {
        throw ("FAILED: $At pushed, and origin's $script:XmipMainBranch is " +
            "'$remote', not this commit, $local.")
    }
}
