#requires -Version 7.6

<#
    The files a node machine is given (node.resource.ps1, kind File): the
    cluster's xmip.toml and the node's certificate, its key private.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Get-NodeFileState {
    <#
    .SYNOPSIS
    Whether a file holds its source's bytes, and whether it is private:
    mode 0600 on Linux, no access rule inherited on Windows.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $state = @{ path = $Instance.path; source = $Instance.source; _exist = $false }

    if (-not (Test-Path -LiteralPath $Instance.path -PathType Leaf)) {
        return $state
    }

    [string] $have = (Get-FileHash -LiteralPath $Instance.path -Algorithm SHA256).Hash
    [string] $want = (Get-FileHash -LiteralPath $Instance.source -Algorithm SHA256).Hash
    $state._exist = $have -eq $want
    $state.private = Test-NodeFilePrivate -Path $Instance.path

    if ($Instance.Contains('private')) {
        $state._exist = $state._exist -and ($state.private -eq [bool] $Instance.private)
    }

    return $state
}

function Test-NodeFilePrivate {
    <#
    .SYNOPSIS
    Whether a file is private: on Linux mode 0600, on Windows in a folder
    that inherits nothing, so only whom that folder names may read it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if ($IsWindows) {
        return (Get-Acl -LiteralPath (Split-Path -Path $Path)).AreAccessRulesProtected
    }

    return (Get-Item -LiteralPath $Path).UnixMode -eq '-rw-------'
}

function Set-NodeFile {
    <#
    .SYNOPSIS
    Copy the source in place. A private file is readable by its owner
    alone: on Linux mode 0600, owned by the node's account; on Windows its
    folder is made to inherit nothing and to admit SYSTEM and the
    administrators, and xmip-service --install --account adds the node's
    account to that folder, so a file copied in later inherits the same.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if (-not $PSCmdlet.ShouldProcess($Instance.path, "Copy $($Instance.source)")) {
        return
    }

    [string] $folder = Split-Path -Path $Instance.path
    [bool] $private = $Instance.Contains('private') -and [bool] $Instance.private
    New-Item -ItemType Directory -Force -Path $folder | Out-Null

    if ($private -and $IsWindows -and -not (Get-Acl -LiteralPath $folder).AreAccessRulesProtected) {
        Invoke-NodeProgram -Program 'icacls.exe' -Argument @(
            $folder, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F',
            '*S-1-5-32-544:(OI)(CI)F'
        ) | Out-Null
    }

    Copy-Item -LiteralPath $Instance.source -Destination $Instance.path -Force

    if (-not $private -or $IsWindows) {
        return
    }

    Invoke-NodeProgram -Program 'chmod' -Argument @('0600', $Instance.path) | Out-Null

    if ($Instance.Contains('owner') -and $Instance.owner) {
        Invoke-NodeProgram -Program 'chown' -Argument @($Instance.owner, $Instance.path) |
            Out-Null
    }
}
