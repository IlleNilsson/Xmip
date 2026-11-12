#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The Machine kind of environment.resource.ps1: a document of this folder
    applied on another machine. A Windows machine is reached over PowerShell
    Remoting, WinRM as its Administrator; an AlmaLinux one over OpenSSH with
    the environment's key and known_hosts, DSC brought to it first
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
    A PowerShell Remoting session on a Windows machine: WinRM as its
    Administrator, the secret file holding its password.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.PSSession])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $winrm = @{
        ComputerName = $Instance.address
        Credential   = Read-MachineSecret -Path $Instance.secretPath
    }
    return New-PSSession @winrm
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
        Invoke-Command -Session $session -ArgumentList $template, $files -ScriptBlock {
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
        [object[]] $argument = @($template, $Instance.document, "$Staging\parameters.yaml",
            $Operation)
        # Windows PowerShell may answer at the far end, so the block asks
        # nothing PowerShell 7 alone has; dsc finds this folder's resources on
        # the PATH it is given.
        return Invoke-Command -Session $session -ArgumentList $argument -ScriptBlock {
            param($Template, $Document, $Parameters, $Operation)
            $env:PATH = "$Template;$env:PATH"
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
