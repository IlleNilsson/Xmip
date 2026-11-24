#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The computers a suite runs on by -ComputerName: each one's file, read and
    refused in one place.

.DESCRIPTION
    A computer's address, account and key belong to this machine and never to
    Git: <name>.toml in the working area's test-computer folder
    (Get-XmipEstateLayout, TestComputer), which -ComputerName names; what was
    sent there is kept beside it, in <name>/ (Send-XmipTestComputerEstate).
    Start-XmipTest, Get-XmipTestStatus, Stop-XmipTest and Get-XmipTestResult
    reach it through Invoke-XmipTestComputer (the owner, 2026-11-23: "Do what
    you recommend"). The computer is Linux (Invoke-XmipTestComputer), reached
    from any computer with OpenSSH's ssh, scp and tar.

    Style: doc/governance/powershell-style.md
#>


# What a computer's file must say: the address ssh connects to, the account
# and the private key's path on this machine.
[string[]] $script:XmipTestComputerKey = @('host', 'user', 'key')

# What it may say, and what it is when it does not: where the estate is
# copied there, under that account's home, and how many builds run there at
# once, each holding one of ~/slot<n>.lock. Defaults, set per computer.
[string] $script:XmipTestComputerFolder = 'xmip-test'
[int] $script:XmipTestComputerSlots = 2


function Read-XmipTestComputer {
    <#
        .SYNOPSIS
            The computer -ComputerName names, as its file says it: Name,
            Host, User, Key, Folder, Slots, File and State, the folder here
            holding what was sent there. REFUSED, naming the file and the
            keys it needs, where the file or a key is not there.

        .PARAMETER Name
            The computer's name, its file's name without .toml.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    [string] $area = (Get-XmipEstateLayout).TestComputer
    [string] $needed = ("host, the address ssh connects to; user, the account there; and " +
        "key, the private key's path here; and may say folder, where the estate is " +
        "copied under that account's home ($script:XmipTestComputerFolder), and slots, " +
        "how many builds run there at once ($script:XmipTestComputerSlots)")

    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw ("REFUSED. $Name is no computer's name: a name is what its file is " +
            "called, $area/<name>.toml.")
    }

    [string] $file = Join-Path -Path $area -ChildPath "$Name.toml"

    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        [string] $known = @(Get-XmipTestComputerChoice -Word '') -join ', '
        [string] $there = if ($known) { " The computers named here: $known." } else { '' }
        throw ("REFUSED. No test computer is called ${Name}: $file is not there. It is " +
            "TOML, kept on this machine and never in Git, and says $needed.$there")
    }

    $read = Read-XmipToml -Path $file
    [string[]] $missing = @(
        $script:XmipTestComputerKey | Where-Object {
            [string]::IsNullOrWhiteSpace([string](Get-TomlValue -Node $read -Name $_ -Default ''))
        }
    )

    if ($missing.Count -gt 0) {
        throw "REFUSED. $file does not say $($missing -join ', '). It says $needed."
    }

    return New-XmipTestComputer -Name $Name -File $file -Read $read -Area $area
}


function New-XmipTestComputer {
    <#
        .SYNOPSIS
            A computer's file, read, as Read-XmipTestComputer returns it: its
            folder, account, host and key checked, the defaults filled in.

        .PARAMETER Read
            What Read-XmipToml read of the file.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $File,

        [Parameter(Mandatory)]
        [object] $Read,

        [Parameter(Mandatory)]
        [string] $Area
    )

    [string] $folder = [string](Get-TomlValue -Node $Read -Name 'folder' -Default (
            $script:XmipTestComputerFolder))
    [int] $slots = [int](Get-TomlValue -Node $Read -Name 'slots' -Default (
            $script:XmipTestComputerSlots))

    # The folder is written into what runs there, so it is a plain relative
    # path under the account's home and nothing a shell reads as more.
    if ($folder -notmatch '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$' -or
        @($folder.Split('/') | Where-Object { $_ -eq '..' }).Count -gt 0) {
        throw "REFUSED. $File says folder = '$folder': a folder under the account's home, as a/b."
    }

    if ($slots -lt 1) {
        throw "REFUSED. $File says slots = ${slots}: at least one build runs there at once."
    }

    # The account and the host are written into ssh's and scp's command
    # line, so neither is anything either reads as an option, `-oProxyCommand`.
    [string] $address = [string](Get-TomlValue -Node $Read -Name 'host')
    [string] $account = [string](Get-TomlValue -Node $Read -Name 'user')

    if ($account -notmatch '^[A-Za-z0-9_][A-Za-z0-9._-]*$') {
        throw ("REFUSED. $File says user = '$account': an account's name, of letters, " +
            "digits, '.', '_' and '-', never beginning with '-'.")
    }

    if ($address -notmatch '^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$') {
        throw ("REFUSED. $File says host = '$address': a host's name, an alias of ssh's " +
            'configuration or an IPv4 address.')
    }

    [string] $key = [string](Get-TomlValue -Node $Read -Name 'key')

    if ($key.StartsWith('~')) {
        $key = Join-Path -Path $HOME -ChildPath $key.Substring(1).TrimStart('/', '\')
    }

    if (-not (Test-Path -LiteralPath $key -PathType Leaf)) {
        throw "REFUSED. $File says key = '$key', and there is no file there."
    }

    return [pscustomobject]@{
        Name   = $Name
        Host   = $address
        User   = $account
        Key    = $key
        Folder = $folder
        Slots  = $slots
        File   = $File
        State  = Join-Path -Path $Area -ChildPath $Name
    }
}


function Get-XmipTestComputerChoice {
    <#
        .SYNOPSIS
            The computers named here whose name starts with -Word, for
            -ComputerName's completion and for a refusal's words.

        .PARAMETER Word
            What has been typed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Word = ''
    )

    [string] $area = (Get-XmipEstateLayout).TestComputer

    if (-not (Test-Path -LiteralPath $area -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $area -Filter '*.toml' -File |
        ForEach-Object { $_.BaseName } |
        Where-Object { $_ -like "$Word*" } |
        Sort-Object
}
