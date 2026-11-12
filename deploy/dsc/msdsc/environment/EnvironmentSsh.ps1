#requires -PSEdition Core
#requires -Version 7.7.0

<#
    How Xmip.Environment/Machine reaches an AlmaLinux machine: OpenSSH's own
    ssh and scp on the machine DSC runs on, with the environment's key and
    its known_hosts, checked strictly, so a machine whose host key is not the
    one its kickstart was given is refused, never trusted on first use. The
    machine needs nothing but its sshd: DSC itself is brought to it here,
    PowerShell 7 and dsc from the tarballs the environment names, each
    checked against its SHA-256 and unpacked under the staging folder, never
    installed for the machine. Dot-sourced by environment.resource.ps1 and by
    test/MsdscEnvironment.Test.ps1.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function ConvertTo-EnvironmentShellWord {
    <#
    .SYNOPSIS
    A value as one word of the machine's POSIX shell: single-quoted.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Value
    )

    return "'" + $Value.Replace("'", "'\''") + "'"
}

function Get-EnvironmentSshOption {
    <#
    .SYNOPSIS
    The options every ssh and scp to the machine is given: its key, the
    environment's known_hosts, strict checking and no prompt.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    return @(
        '-i', $Instance.keyPath,
        '-o', "UserKnownHostsFile=$($Instance.knownHosts)",
        '-o', 'StrictHostKeyChecking=yes',
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=10'
    )
}

function Invoke-EnvironmentSsh {
    <#
    .SYNOPSIS
    Run a command line in the machine's shell as its login and answer what
    it wrote; a failure is refused with what it said. -Trace names a file
    its standard error goes to instead of the refusal.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [string] $Command,

        [Parameter()]
        [string] $Trace = ''
    )

    [string] $said = if ($Trace) { $Trace } else { [IO.Path]::GetTempFileName() }
    try {
        [string[]] $argument = @(Get-EnvironmentSshOption -Instance $Instance) + @(
            "$($Instance.login)@$($Instance.address)", '--', $Command)
        [string[]] $out = @(& ssh @argument 2> $said | ForEach-Object { "$_" })
        if ($LASTEXITCODE -ne 0) {
            [string] $why = (Get-Content -LiteralPath $said -Tail 5) -join ' '
            throw "REFUSED: $($Instance.name): ssh exited $LASTEXITCODE`: $why"
        }
        return $out
    }
    finally {
        if (-not $Trace) {
            Remove-Item -LiteralPath $said -Force -ErrorAction Ignore
        }
    }
}

function Send-EnvironmentFile {
    <#
    .SYNOPSIS
    Copy each file to the machine, under its name in the folder there, where
    the machine does not hold its bytes already: what a node is given, the
    template and the tools are sent once, not at every test.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $File,

        [Parameter(Mandatory = $true)]
        [string] $Folder
    )

    [string[]] $names = @($File.Keys)
    if ($names.Count -eq 0) {
        return
    }
    [string] $words = ($names | ForEach-Object {
            ConvertTo-EnvironmentShellWord -Value "$Folder/$_" }) -join ' '
    [hashtable] $held = @{}
    foreach ($line in @(Invoke-EnvironmentSsh -Instance $Instance -Command (
                "sha256sum -- $words 2>/dev/null; true"))) {
        [string[]] $field = @($line -split '\s+', 2)
        if ($field.Count -eq 2) {
            $held[$field[1].TrimStart('*')] = $field[0]
        }
    }
    foreach ($name in $names) {
        [string] $remote = "$Folder/$name"
        [string] $want = (Get-FileHash -LiteralPath $File[$name] -Algorithm SHA256).Hash
        if ($held.ContainsKey($remote) -and $held[$remote] -eq $want.ToLowerInvariant()) {
            continue
        }
        [string[]] $argument = @(Get-EnvironmentSshOption -Instance $Instance) + @(
            '-q', $File[$name], "$($Instance.login)@$($Instance.address):$remote")
        [string] $said = (& scp @argument 2>&1) -join ' '
        if ($LASTEXITCODE -ne 0) {
            throw "REFUSED: $($Instance.name): scp of $($File[$name]) exited $LASTEXITCODE`: $said"
        }
    }
}

function Install-EnvironmentTool {
    <#
    .SYNOPSIS
    Bring DSC to the machine: each tool's tarball, refused where its SHA-256
    is not the one the environment names, sent to the staging folder's tools
    and unpacked there in a folder of its name, again only where it changed.
    Answers the folders, for the PATH dsc runs with.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [string] $Staging
    )

    [System.Collections.IDictionary] $tool = $Instance.tools
    [Collections.Specialized.OrderedDictionary] $tarball = [ordered] @{}
    [string[]] $unpack = @()
    foreach ($name in @($tool.Keys | Sort-Object)) {
        [string] $path = $tool[$name].path
        [string] $sha256 = $tool[$name].sha256.ToLowerInvariant()
        [string] $have = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($have -ne $sha256) {
            throw "REFUSED: $path has SHA-256 $have, not $sha256."
        }
        $tarball["$name.tar.gz"] = $path
        [string] $into = ConvertTo-EnvironmentShellWord -Value "$Staging/tools/$name"
        [string] $from = ConvertTo-EnvironmentShellWord -Value "$Staging/tools/$name.tar.gz"
        [string] $mark = ConvertTo-EnvironmentShellWord -Value "$Staging/tools/$name/.sha256"
        $unpack += "if [ `"`$(cat $mark 2>/dev/null)`" != '$sha256' ]; then " +
            "rm -rf $into && mkdir -p $into && tar -xzf $from -C $into && " +
            "echo '$sha256' > $mark; fi"
    }
    Send-EnvironmentFile -Instance $Instance -File $tarball -Folder "$Staging/tools"
    Invoke-EnvironmentSsh -Instance $Instance -Command ('set -e; ' + ($unpack -join '; ')) |
        Out-Null
    return @($tool.Keys | Sort-Object | ForEach-Object { "$Staging/tools/$_" })
}

function Invoke-EnvironmentSshDocument {
    <#
    .SYNOPSIS
    Apply or test a document on an AlmaLinux machine: the template, the
    node's files and DSC sent to its staging folder, its parameters written
    there, and dsc run there with sudo, its PATH the tools and the template,
    so dsc finds this folder's resources and PowerShell 7 runs them.
    Answers what dsc wrote, its JSON.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [ValidateSet('test', 'set')]
        [string] $Operation,

        [Parameter(Mandatory = $true)]
        [string] $Staging,

        [Parameter(Mandatory = $true)]
        [string] $Parameters
    )

    [string] $quoted = ConvertTo-EnvironmentShellWord -Value $Staging
    # The staging folder is this login's alone, 0700, the files folder too:
    # one another account made or owns is refused, never written into.
    Invoke-EnvironmentSsh -Instance $Instance -Command (
        "mkdir -p -m 0700 $quoted && { [ -O $quoted ] || { echo 'REFUSED: $Staging is not " +
        "owned by this login' >&2; exit 3; }; } && chmod 0700 $quoted && " +
        "mkdir -p $quoted/template $quoted/files $quoted/tools && chmod 0700 $quoted/files") |
        Out-Null
    [Collections.Specialized.OrderedDictionary] $template = [ordered] @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $PSScriptRoot -File)) {
        $template[$file.Name] = $file.FullName
    }
    Send-EnvironmentFile -Instance $Instance -File $template -Folder "$Staging/template"
    Send-EnvironmentFile -Instance $Instance -File $Instance.files -Folder "$Staging/files"
    Send-EnvironmentFile -Instance $Instance -File ([ordered] @{
            'parameters.yaml' = $Parameters }) -Folder $Staging
    [string[]] $path = @(Install-EnvironmentTool -Instance $Instance -Staging $Staging) + @(
        "$Staging/template", '/usr/local/sbin', '/usr/local/bin', '/usr/sbin', '/usr/bin')
    # What the node is given, its key among it, is read by this login and
    # root alone while dsc runs, and removed once it has run, whatever it
    # answered: the next run sends it again.
    [string] $files = ConvertTo-EnvironmentShellWord -Value "$Staging/files"
    [string] $command = @(
        "chmod -R go-rwx $files &&",
        'sudo', 'env', (ConvertTo-EnvironmentShellWord -Value "PATH=$($path -join ':')"),
        # PowerShell 7 without the ICU library a minimal machine may lack.
        'DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1',
        'dsc', 'config', '--parameters-file', "$quoted/parameters.yaml", $Operation,
        '--file', (ConvertTo-EnvironmentShellWord -Value "$Staging/template/$($Instance.document)"),
        "; status=`$?; rm -rf -- $files; exit `$status"
    ) -join ' '
    [string] $trace = [IO.Path]::GetTempFileName()
    try {
        [hashtable] $asked = @{ Instance = $Instance; Command = $command; Trace = $trace }
        return (Invoke-EnvironmentSsh @asked) -join "`n"
    }
    catch {
        [string] $why = (Get-Content -LiteralPath $trace | Where-Object { $_ -match 'ERROR' } |
            Select-Object -Last 3) -join ' '
        throw "$($_.Exception.Message) $why"
    }
    finally {
        Remove-Item -LiteralPath $trace -Force -ErrorAction Ignore
    }
}
