#requires -Version 7.6

<#
    The Machine kind of environment.resource.ps1: a document of this folder
    applied on another machine. Dot-sourced by environment.resource.ps1 and
    by test/MsdscEnvironment.Test.ps1.

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

function New-EnvironmentSession {
    <#
    .SYNOPSIS
    A PowerShell Remoting session on the machine: WinRM as its
    Administrator for Windows, SSH with its key for AlmaLinux.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.PSSession])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if ($Instance.family -eq 'Windows') {
        [hashtable] $winrm = @{
            ComputerName = $Instance.address
            Credential   = Import-Clixml -LiteralPath $Instance.credentialPath
        }
        return New-PSSession @winrm
    }

    [hashtable] $ssh = @{
        HostName    = $Instance.address
        UserName    = $Instance.login
        KeyFilePath = $Instance.keyPath
        SSHTransport = $true
    }
    return New-PSSession @ssh
}

function Copy-EnvironmentDocument {
    <#
    .SYNOPSIS
    Copy this folder, the document's files and its parameters to the
    machine's staging folder, and answer the parameters file's path there.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $staging = Get-EnvironmentStaging -Family $Instance.family
    [string] $separator = if ($Instance.family -eq 'Windows') { '\' } else { '/' }
    [string] $template = "$staging${separator}template"
    [string] $files = "$staging${separator}files"

    Invoke-Command -Session $Session -ArgumentList $template, $files -ScriptBlock {
        param($Template, $Files)
        Remove-Item -LiteralPath $Template -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $Template, $Files | Out-Null
    }
    [hashtable] $folder = @{
        Path        = Join-Path -Path $PSScriptRoot -ChildPath '*'
        Destination = $template
        ToSession   = $Session
        Recurse     = $true
    }
    Copy-Item @folder

    foreach ($name in @($Instance.files.Keys)) {
        [hashtable] $copy = @{
            Path        = $Instance.files[$name]
            Destination = "$files$separator$name"
            ToSession   = $Session
            Recurse     = $true
            Force       = $true
        }
        Copy-Item @copy
    }

    [hashtable] $parameters = $Instance.parameters.Clone()
    $parameters.staging = $staging
    [string] $json = @{ parameters = $parameters } | ConvertTo-Json -Depth 10
    [string] $file = "$staging${separator}parameters.json"
    Invoke-Command -Session $Session -ArgumentList $file, $json -ScriptBlock {
        param($File, $Json)
        [System.IO.File]::WriteAllText($File, $Json)
    }

    return $file
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
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [ValidateSet('test', 'set')]
        [string] $Operation
    )

    [string] $parameters = Copy-EnvironmentDocument -Session $Session -Instance $Instance
    [string] $staging = Get-EnvironmentStaging -Family $Instance.family
    [object[]] $argument = @($Instance.family, $staging, $Instance.document, $parameters, $Operation)

    # Windows PowerShell may answer at the far end, so the block asks
    # nothing PowerShell 7 alone has; dsc finds this folder's resources on
    # the PATH it is given.
    [string] $said = Invoke-Command -Session $Session -ArgumentList $argument -ScriptBlock {
        param($Family, $Staging, $Document, $Parameters, $Operation)
        $windows = $Family -eq 'Windows'
        $template = if ($windows) { "$Staging\template" } else { "$Staging/template" }
        $file = if ($windows) { "$template\$Document" } else { "$template/$Document" }
        $config = @('config', '--parameters-file', $Parameters, $Operation, '--file', $file)
        if ($windows) {
            $env:PATH = "$template;$env:PATH"
            return (& dsc @config) -join "`n"
        }
        return (& sudo env "PATH=${template}:$env:PATH" dsc @config) -join "`n"
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

    $session = New-EnvironmentSession -Instance $Instance

    [hashtable] $asked = @{ Session = $session; Instance = $Instance; Operation = 'test' }

    try {
        [hashtable] $tested = Invoke-EnvironmentDocument @asked
    }
    finally {
        Remove-PSSession -Session $session
    }

    [hashtable] $state = $Instance.Clone()
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
        $session = New-EnvironmentSession -Instance $Instance

        try {
            Invoke-EnvironmentDocument -Session $session -Instance $Instance -Operation set | Out-Null
        }
        finally {
            Remove-PSSession -Session $session
        }
    }

    return Get-EnvironmentMachine -Instance $Instance
}
