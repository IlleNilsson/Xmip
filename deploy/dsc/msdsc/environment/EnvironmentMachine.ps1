#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The Machine kind of environment.resource.ps1: a document of this folder
    applied on another machine, DSC brought to it first. A Windows machine
    is reached over PowerShell Remoting as its Administrator; an AlmaLinux
    one over OpenSSH with the environment's key and known_hosts
    (EnvironmentSsh.ps1). Dot-sourced by environment.resource.ps1 and by
    test/MsdscEnvironment.Test.ps1.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

function Get-EnvironmentStaging {
    <#
    .SYNOPSIS
    Where on the machine this folder and a document's files are copied:
    the machine's own, never one a node reads.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Windows', 'Linux')]
        [string] $Family
    )

    if ($Family -eq 'Windows') {
        return 'C:\ProgramData\Xmip\environment'
    }

    return '/var/tmp/xmip-environment'
}

function Write-EnvironmentParameter {
    <#
    .SYNOPSIS
    The document's parameters, given the staging folder, written here as
    YAML, configuration as dsc takes it (CONTRIBUTING), by powershell-yaml:
    the machine needs no module. Answers the file's path; the caller removes
    it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [string] $Staging
    )

    [hashtable] $parameters = $Instance.parameters.Clone()
    $parameters.staging = $Staging
    Import-Module -Name powershell-yaml
    [string] $file = [IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($file, (@{ parameters = $parameters } | ConvertTo-Yaml))
    return $file
}

function New-EnvironmentSession {
    <#
    .SYNOPSIS
    A PowerShell Remoting session on a Windows machine as its Administrator,
    the secret file holding its password: PowerShell Direct where this host
    runs the machine on Hyper-V, which needs no network, no WinRM listener
    and no TrustedHosts entry, only the Hyper-V Administrators group; WinRM
    to its address otherwise. Where the instance names the environment's
    domain, a machine the plain name is refused on is logged on to as
    Administrator@<domain>, as a domain controller is.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.PSSession])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [pscredential] $administrator = Read-MachineSecret -Path $Instance.secretPath
    [string] $name = [string] $Instance['name']
    [hashtable] $reach = if ($name -and (Get-Command -Name Get-VM -ErrorAction SilentlyContinue) -and
        (Get-VM -Name $name -ErrorAction SilentlyContinue)) { @{ VMName = $name } }
    else { @{ ComputerName = $Instance.address } }
    [string] $domain = [string] $Instance['domain']
    if (-not $domain) {
        return New-PSSession @reach -Credential $administrator
    }
    # A domain controller has no Administrator of its own: promoting it made
    # its Administrator the domain's, the same secret, which the plain name
    # no longer logs on as (2026-11-21, the Hyper-V environment's XMIP-DC01).
    try {
        return New-PSSession @reach -Credential $administrator -ErrorAction Stop
    }
    catch {
        [pscredential] $domainAdministrator = [pscredential]::new(
            "$($administrator.UserName)@$domain", $administrator.Password)
        return New-PSSession @reach -Credential $domainAdministrator
    }
}

function Invoke-EnvironmentCommand {
    <#
    .SYNOPSIS
    A script block run on a Windows machine over its session, answering what
    it outputs; what it warns of or writes otherwise there comes back as this
    side's own, which environment.resource.ps1 sends to standard error. Left
    to PowerShell Remoting, a warning there reaches this host's console,
    standard output, where DSC reads the JSON, past every redirection and
    -WarningAction here (2026-11-23, Add-Computer's at a domain join).
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(Mandatory = $true)]
        [scriptblock] $ScriptBlock,

        [Parameter()]
        [object[]] $ArgumentList = @()
    )

    # The block goes as its text, made again there, where Windows PowerShell
    # may answer; every stream but errors is output there, each record told
    # apart here by its type and read as its text, all a record keeps across.
    [object[]] $sent = @([string] $ScriptBlock) + $ArgumentList
    [string] $record = 'Deserialized.System.Management.Automation.'
    Invoke-Command -Session $Session -ArgumentList $sent -ScriptBlock {
        param($Text)
        & ([scriptblock]::Create($Text)) @args 3>&1 4>&1 5>&1 6>&1
    } | ForEach-Object {
        [string[]] $type = if ($null -eq $_) { @() } else { $_.PSObject.TypeNames }
        if ($type -contains "${record}WarningRecord") {
            Write-Warning -Message ([string] $_)
        }
        elseif ($type -contains "${record}VerboseRecord") {
            Write-Verbose -Message ([string] $_)
        }
        elseif ($type -contains "${record}DebugRecord") {
            Write-Debug -Message ([string] $_)
        }
        elseif ($type -contains "${record}InformationRecord") {
            Write-Information -MessageData ([string] $_)
        }
        else {
            $_
        }
    }
}

function Assert-EnvironmentToolDigest {
    <#
    .SYNOPSIS
    A tool DSC is brought to a machine with, refused where its file's
    SHA-256 is not the one the environment names, before anything is sent;
    answers that SHA-256, lower case. Both families' installs ask it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Tool
    )

    [string] $sha256 = ([string] $Tool.sha256).ToLowerInvariant()
    [string] $have = (Get-FileHash -LiteralPath $Tool.path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($have -ne $sha256) {
        throw "REFUSED: $($Tool.path) has SHA-256 $have, not $sha256."
    }
    return $sha256
}

function Install-EnvironmentWindowsTool {
    <#
    .SYNOPSIS
    Bring DSC to a Windows machine, as EnvironmentSsh.ps1 brings it to an
    AlmaLinux one: each tool's zip, refused where its SHA-256 is not the one
    the environment names, sent to the staging folder's tools and unpacked
    there in a folder of its name, only where the folder holds another.
    Answers the folders, for the PATH dsc runs with.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(Mandatory = $true)]
        [string] $Staging
    )

    [System.Collections.IDictionary] $tool = $Instance['tools']
    if ($null -eq $tool) {
        return @()
    }
    [string[]] $folders = @()
    foreach ($name in @($tool.Keys | Sort-Object)) {
        [string] $path = $tool[$name].path
        [string] $sha256 = Assert-EnvironmentToolDigest -Tool $tool[$name]
        [string] $into = "$Staging\tools\$name"
        [string] $mark = "$into\.sha256"
        [hashtable] $asked = @{ Session = $Session; ArgumentList = $mark }
        [string] $held = Invoke-EnvironmentCommand @asked -ScriptBlock {
            param($Mark)
            if (Test-Path -LiteralPath $Mark) { (Get-Content -LiteralPath $Mark -Raw).Trim() }
        }
        if ($held -ne $sha256) {
            [string] $zip = "$Staging\tools\$name.zip"
            Invoke-EnvironmentCommand -Session $Session -ArgumentList $into -ScriptBlock {
                param($Into)
                Remove-Item -LiteralPath $Into -Recurse -Force -ErrorAction SilentlyContinue
                New-Item -ItemType Directory -Force -Path $Into | Out-Null
            }
            Copy-Item -Path $path -Destination $zip -ToSession $Session -Force
            [object[]] $unpacked = @($zip, $into, $mark, $sha256)
            Invoke-EnvironmentCommand -Session $Session -ArgumentList $unpacked -ScriptBlock {
                param($Zip, $Into, $Mark, $Sha256)
                Expand-Archive -LiteralPath $Zip -DestinationPath $Into -Force
                Remove-Item -LiteralPath $Zip -Force
                Set-Content -LiteralPath $Mark -Value $Sha256
            }
        }
        $folders += $into
    }
    return $folders
}

function Invoke-EnvironmentWinRmDocument {
    <#
    .SYNOPSIS
    Apply or test a document on a Windows machine over PowerShell Remoting:
    this folder, the document's files and its parameters copied to the
    staging folder, and dsc run there as the Administrator. Answers what dsc
    wrote, its JSON.
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

    $session = New-EnvironmentSession -Instance $Instance
    try {
        [string] $template = "$Staging\template"
        [string] $files = "$Staging\files"
        Invoke-EnvironmentCommand -Session $session -ArgumentList $template, $files -ScriptBlock {
            param($Template, $Files)
            Remove-Item -LiteralPath $Template -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Force -Path $Template, $Files | Out-Null
        }
        [hashtable] $folder = @{
            Path        = Join-Path -Path $PSScriptRoot -ChildPath '*'
            Destination = $template
            ToSession   = $session
            Recurse     = $true
        }
        Copy-Item @folder
        foreach ($name in @($Instance.files.Keys)) {
            Copy-Item -Path $Instance.files[$name] -Destination "$files\$name" -ToSession (
                $session) -Force
        }
        Copy-Item -Path $Parameters -Destination "$Staging\parameters.yaml" -ToSession $session
        [string[]] $tools = @(Install-EnvironmentWindowsTool -Instance $Instance -Session (
                $session) -Staging $Staging)
        [string] $path = (@($tools) + $template) -join ';'
        [object[]] $argument = @($path, $template, $Instance.document,
            "$Staging\parameters.yaml", $Operation)
        # Windows PowerShell may answer at the far end, so the block asks
        # nothing PowerShell 7 alone has; dsc and PowerShell 7 are found in the
        # tools, this folder's resources in the template, on the PATH given.
        return Invoke-EnvironmentCommand -Session $session -ArgumentList $argument -ScriptBlock {
            param($Path, $Template, $Document, $Parameters, $Operation)
            $env:PATH = "$Path;$env:PATH"
            $config = @('config', '--parameters-file', $Parameters, $Operation, '--file',
                "$Template\$Document")
            return (& dsc @config) -join "`n"
        }
    }
    finally {
        Remove-PSSession -Session $session
    }
}

function Invoke-EnvironmentDocument {
    <#
    .SYNOPSIS
    Run dsc on the machine, elevated, over the copied document: test
    answers whether every instance is as asked and which are not, set
    makes them so.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [ValidateSet('test', 'set')]
        [string] $Operation
    )

    [string] $staging = Get-EnvironmentStaging -Family $Instance.family
    [string] $parameters = Write-EnvironmentParameter -Instance $Instance -Staging $staging
    [hashtable] $asked = @{
        Instance = $Instance
        Operation = $Operation
        Staging = $staging
        Parameters = $parameters
    }
    try {
        [string] $said = if ($Instance.family -eq 'Windows') {
            Invoke-EnvironmentWinRmDocument @asked
        }
        else {
            Invoke-EnvironmentSshDocument @asked
        }
    }
    finally {
        Remove-Item -LiteralPath $parameters -Force -ErrorAction Ignore
    }

    [hashtable] $result = $said | ConvertFrom-Json -AsHashtable
    [string[]] $differing = @($result.results | Where-Object {
            $_.result.Contains('inDesiredState') -and -not $_.result.inDesiredState
        } | ForEach-Object { $_.name })

    return @{
        inDesiredState = -not $result.hadErrors -and $differing.Count -eq 0
        differing      = $differing
    }
}

function Get-EnvironmentMachine {
    <#
    .SYNOPSIS
    The machine's state: _exist where the document's every instance there
    is as asked, and which are not.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $state = $Instance.Clone()
    # A machine not answering yet, as before it is installed, is answered
    # absent, never refused, so a fresh host is tested too.
    [int] $port = if ($Instance.family -eq 'Windows') { 5985 } else { 22 }
    [hashtable] $reach = @{ TargetName = $Instance.address; TcpPort = $port; TimeoutSeconds = 1 }
    if (-not (Test-Connection @reach -Quiet)) {
        $state._exist = $false
        $state.differing = @("$($Instance.name) does not answer on port $port")
        return $state
    }
    [hashtable] $tested = Invoke-EnvironmentDocument -Instance $Instance -Operation test
    $state._exist = $tested.inDesiredState
    $state.differing = $tested.differing
    return $state
}

function Set-EnvironmentMachine {
    <#
    .SYNOPSIS
    Apply the document on the machine, then answer its state as tested.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if ($PSCmdlet.ShouldProcess($Instance.name, "Apply $($Instance.document)")) {
        Invoke-EnvironmentDocument -Instance $Instance -Operation set | Out-Null
    }

    return Get-EnvironmentMachine -Instance $Instance
}
