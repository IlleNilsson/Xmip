#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipDeployStateFolder {
    <#
        .SYNOPSIS
            Where an environment's private state is kept on the machine
            deploying it: on Linux and macOS under $XDG_STATE_HOME, or
            ~/.local/state, xmip/deploy/<environment>, since a file on a
            Windows drive mounted in WSL shows as 0777 there and OpenSSH
            refuses a private key others may read; on Windows in the run
            folder, state, whose access rules are made this account's alone.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Run
    )

    if ($IsWindows) {
        return Join-Path $Run 'state'
    }
    [string] $base = if ($env:XDG_STATE_HOME) { $env:XDG_STATE_HOME }
    else { Join-Path $HOME '.local/state' }
    return Join-Path $base "xmip/deploy/$Name"
}

function Initialize-XmipDeployState {
    <#
        .SYNOPSIS
            An environment's private state on the machine deploying it, made
            where it is not, in the folder the run holds
            (Lock-XmipDeployState): the technology that makes the
            environment, so the other one is refused; the environment's own
            SSH key, which its AlmaLinux machines' account is given by their
            kickstart and is reached with, readable by this account alone
            and with no passphrase, so a deployment runs unattended; each
            such machine's SSH host key, made here before it is installed
            and given to it by its kickstart; and known_hosts holding
            exactly those keys, so every login checks the machine it reaches
            and none trusts on first use.

        .DESCRIPTION
            An environment is made by one technology, never a mix (ADR-0015,
            amendment 2026-10-09): the first run that applies writes it in
            the folder's technology, and a run of the other one, -WhatIf
            too, is refused before anything is written, until the
            environment is removed (deploy/dsc/README.md, Starting again
            from nothing). OpenSSH is the machines' own and the
            hypervisors', so this takes the platform's way: Xmip has no SSH
            of its own. The keys are kept for as long as the folder is, so a
            machine installed again is reached with the same key and answers
            with the host key known_hosts already holds; a person reaches a
            machine with the environment's key, ssh -i
            <folder>/ssh/id_ed25519.

        .PARAMETER Environment
            The environment file, as Read-XmipToml reads it.

        .PARAMETER Folder
            The state folder, Get-XmipDeployStateFolder's, which this run
            holds.

        .PARAMETER Technology
            msdsc or ansible, the environment file's.

        .PARAMETER Record
            Writes the technology where the folder names none: a run that
            applies, never one that only tests.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment,

        [Parameter(Mandatory)]
        [string] $Folder,

        [Parameter(Mandatory)]
        [ValidateSet('msdsc', 'ansible')]
        [string] $Technology,

        [Parameter()]
        [switch] $Record
    )

    [string] $name = Get-TomlValue -Node $Environment -Name 'name'
    [string] $made = Join-Path $Folder 'technology'
    if (Test-Path -LiteralPath $made -PathType Leaf) {
        [string] $by = (Get-Content -LiteralPath $made -Raw).Trim()
        if ($by -ne $Technology) {
            throw ("REFUSED: $name was made by $by, not $Technology`: an environment is made " +
                'by one technology, never a mix. Remove it first (deploy/dsc/README.md, ' +
                "Starting again from nothing), its state folder too: $Folder")
        }
    }
    elseif ($Record) {
        [IO.File]::WriteAllText($made, "$Technology`n", [Text.UTF8Encoding]::new($false))
    }
    foreach ($each in (Join-Path $Folder 'ssh'), (Join-Path $Folder 'host')) {
        New-Item -Path $each -ItemType Directory -Force -WhatIf:$false | Out-Null
        Protect-XmipDeployPath -Path $each
    }
    [string] $key = Join-Path $Folder 'ssh/id_ed25519'
    New-XmipDeployKey -Path $key -Comment "xmip-$name"
    [hashtable] $hostKey = @{}
    [string[]] $known = @()
    $images = Get-TomlValue -Node $Environment -Name 'images'
    foreach ($machine in @(Get-TomlValue -Node $Environment -Name 'machines' -Default @())) {
        $image = Get-TomlValue -Node $images -Name (Get-TomlValue -Node $machine -Name 'image')
        if ((Get-TomlValue -Node $image -Name 'family') -ne 'Linux') {
            continue
        }
        [string] $machineName = Get-TomlValue -Node $machine -Name 'name'
        [string] $path = Join-Path $Folder "host/$machineName"
        New-XmipDeployKey -Path $path -Comment $machineName
        $hostKey[$machineName] = $path
        [string[]] $field = @((Get-Content -LiteralPath "$path.pub" -Raw).Trim() -split '\s+')
        [string] $address = Get-TomlValue -Node $machine -Name 'address'
        $known += "$machineName,$address $($field[0]) $($field[1])"
    }
    [string] $knownHosts = Join-Path $Folder 'known_hosts'
    [IO.File]::WriteAllText($knownHosts, (($known + '') -join "`n"),
        [Text.UTF8Encoding]::new($false))
    return @{ Folder = $Folder; Key = $key; KnownHosts = $knownHosts; HostKey = $hostKey }
}

function Lock-XmipDeployState {
    <#
        .SYNOPSIS
            The environment's private state folder, made where it is not,
            readable by this account alone, and held for this run alone
            through run.lock in it, until the stream answered is disposed: a
            second run of the environment is refused while one runs, before
            it writes anything there, so two never install its machines or
            start its nodes at once and a run's keys and known_hosts never
            change under it.

        .DESCRIPTION
            Opened sharing nothing: on Windows a sharing violation, on Linux
            and macOS an flock .NET takes, either released when the process
            ends, however it ends. A run refused names the file.
    #>
    [CmdletBinding()]
    [OutputType([IO.FileStream])]
    param(
        [Parameter(Mandatory)]
        [string] $Folder
    )

    New-Item -Path $Folder -ItemType Directory -Force -WhatIf:$false | Out-Null
    Protect-XmipDeployPath -Path $Folder
    [string] $path = Join-Path $Folder 'run.lock'
    try {
        return [IO.FileStream]::new($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None)
    }
    catch {
        [Exception] $failure = $_.Exception
        while ($failure -is [Management.Automation.MethodInvocationException] -and
            $null -ne $failure.InnerException) {
            $failure = $failure.InnerException
        }
        # A folder or file not found is no other run.
        if ($failure.GetType() -ne [IO.IOException]) {
            throw
        }
        throw "REFUSED: another run of this environment holds $path; one runs at a time."
    }
}

function New-XmipDeployKey {
    <#
        .SYNOPSIS
            An ed25519 key pair at -Path and -Path.pub, made by OpenSSH's
            ssh-keygen where it is not there, with no passphrase, the
            private half this account's alone.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Comment
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        [string[]] $made = @(& ssh-keygen -q -t ed25519 -N '' -C $Comment -f $Path 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "REFUSED: ssh-keygen could not make the key $Path`: $made"
        }
    }
    Protect-XmipDeployPath -Path $Path
}

function Protect-XmipDeployPath {
    <#
        .SYNOPSIS
            A file or folder of the private state made this account's alone:
            mode 0600, or 0700 for a folder, on Linux and macOS; on Windows
            its inherited access rules removed and full control left to this
            account, which needs no elevation on what it owns.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    [bool] $isFolder = Test-Path -LiteralPath $Path -PathType Container
    if (-not $IsWindows) {
        [IO.UnixFileMode] $mode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite
        if ($isFolder) {
            $mode = $mode -bor [IO.UnixFileMode]::UserExecute
        }
        [IO.File]::SetUnixFileMode($Path, $mode)
        return
    }
    # The access rules alone: the audit rules need a privilege an account
    # setting its own files does not hold.
    [IO.FileSystemInfo] $item = if ($isFolder) { [IO.DirectoryInfo]::new($Path) }
    else { [IO.FileInfo]::new($Path) }
    $acl = [IO.FileSystemAclExtensions]::GetAccessControl($item,
        [Security.AccessControl.AccessControlSections]::Access)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.GetAccessRules($true, $true, [Security.Principal.NTAccount]))) {
        $acl.RemoveAccessRule($rule) | Out-Null
    }
    [string] $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    [Security.AccessControl.InheritanceFlags] $inherit = if ($isFolder) {
        'ContainerInherit, ObjectInherit'
    }
    else { 'None' }
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $me, 'FullControl', $inherit, 'None', 'Allow'))
    [IO.FileSystemAclExtensions]::SetAccessControl($item, $acl)
}
