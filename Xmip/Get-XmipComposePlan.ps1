#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Where each repository mounts, where it is mounted now, and what composing would change.

.DESCRIPTION
    Apart from Sync-XmipEstate.ps1 since 2026-09-22, when that file was 1,303 lines
    against the 400 the estate allows, and the owner asked for the estate to be
    consolidated. Reconciling the estate is one command made of several subjects;
    each subject is a file.

    Style: doc/governance/powershell-style.md
#>


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
        [string[]] $output = @(
            Invoke-Native -FilePath 'git' -Arguments $arguments -At $Root -CaptureOutput
        )

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
