#requires -PSEdition Core
#requires -Version 7.7.0

<#
    Who may write the node's node.xmip (node.resource.ps1, kind Slice): the
    file is the node's alone to write (ADR-0031, amendment 2026-11-06, point
    4). On Windows it inherits nothing, SYSTEM and the administrators hold
    it in full and the node's service account may modify it; on Linux it is
    the account's, group root, mode 0640. Dot-sourced by node.resource.ps1
    and by test/MsdscEnvironment.Test.ps1.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Get-NodeAccountSid {
    <#
    .SYNOPSIS
    The security identifier of a Windows account. A service's virtual
    account, NT SERVICE\<service>, is computed, as Windows computes it: it
    exists only once the package has registered the service, and its slice
    is placed before that. Any other account is looked up.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Account
    )

    if ($Account -match '^NT SERVICE\\(?<service>.+)$') {
        # S-1-5-80, then the SHA-1 of the service's name, upper case in
        # UTF-16, as five 32-bit little-endian numbers.
        [byte[]] $name = [System.Text.Encoding]::Unicode.GetBytes(
            $Matches['service'].ToUpperInvariant())
        [byte[]] $hash = [System.Security.Cryptography.SHA1]::HashData($name)
        [uint32[]] $part = @(0..4 | ForEach-Object {
                [System.BitConverter]::ToUInt32($hash, $_ * 4)
            })
        return "S-1-5-80-$($part -join '-')"
    }

    [System.Security.Principal.NTAccount] $named = [System.Security.Principal.NTAccount]::new(
        $Account)
    return $named.Translate([System.Security.Principal.SecurityIdentifier]).Value
}

function Get-NodeSliceWanted {
    <#
    .SYNOPSIS
    Who may write node.xmip, as get and test say it: on Windows each access
    rule as <SID>:<rights> and "protected", that it inherits nothing; on
    Linux owner:group and the mode.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Account
    )

    if (-not $IsWindows) {
        return @("$($Account):root", '0640')
    }

    [string] $node = Get-NodeAccountSid -Account $Account
    return @('protected', 'S-1-5-18:FullControl', 'S-1-5-32-544:FullControl',
        "$($node):Modify, Synchronize" | Sort-Object)
}

function Get-NodeSliceAccess {
    <#
    .SYNOPSIS
    Who may write node.xmip as it is found, in Get-NodeSliceWanted's words;
    none where the file is not there.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @()
    }

    if (-not $IsWindows) {
        [string] $owner = (& stat -c '%U:%G' $Path) -join ''
        [string] $mode = (& stat -c '%a' $Path) -join ''
        return @($owner, $mode.PadLeft(4, '0'))
    }

    [System.IO.FileInfo] $file = [System.IO.FileInfo]::new($Path)
    $security = [System.IO.FileSystemAclExtensions]::GetAccessControl(
        $file, [System.Security.AccessControl.AccessControlSections]::Access)
    [type] $sid = [System.Security.Principal.SecurityIdentifier]
    [string[]] $found = @($security.GetAccessRules($true, $true, $sid) | ForEach-Object {
            [string] $kind = if ($_.IsInherited) { 'inherited ' } else { '' }
            "$kind$($_.IdentityReference.Value):$($_.FileSystemRights)"
        })

    if ($security.AreAccessRulesProtected) {
        $found += 'protected'
    }

    return @($found | Sort-Object)
}

function Set-NodeSliceAccess {
    <#
    .SYNOPSIS
    Make node.xmip the node's alone to write: on Windows inheriting nothing,
    SYSTEM and the administrators in full control and the account with
    Modify, every other rule gone; on Linux the account's, group root, mode
    0640.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Account
    )

    if (-not $PSCmdlet.ShouldProcess($Path, "Make it writable by $Account and administrators")) {
        return
    }

    if (-not $IsWindows) {
        Invoke-DscProgram -Program 'chown' -Argument @("$($Account):root", $Path) | Out-Null
        Invoke-DscProgram -Program 'chmod' -Argument @('0640', $Path) | Out-Null
        return
    }

    [System.IO.FileInfo] $file = [System.IO.FileInfo]::new($Path)
    $security = [System.Security.AccessControl.FileSecurity]::new()
    $security.SetAccessRuleProtection($true, $false)
    [hashtable] $right = [ordered] @{
        'S-1-5-18'                             = 'FullControl'
        'S-1-5-32-544'                         = 'FullControl'
        (Get-NodeAccountSid -Account $Account) = 'Modify'
    }

    foreach ($holder in $right.Keys) {
        [System.Security.AccessControl.FileSystemAccessRule] $rule = (
            [System.Security.AccessControl.FileSystemAccessRule]::new(
                [System.Security.Principal.SecurityIdentifier]::new($holder),
                [System.Security.AccessControl.FileSystemRights] $right[$holder],
                [System.Security.AccessControl.AccessControlType]::Allow))
        $security.AddAccessRule($rule)
    }

    # The access list alone: the owner stays whoever made the file.
    [System.IO.FileSystemAclExtensions]::SetAccessControl($file, $security)
}
