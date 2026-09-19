#Requires -Version 7.6.5

# Every System Process Xmip owns, with what it says of itself (ADR-0053).

function Get-XmipProcessDirectory {
    <#
        .SYNOPSIS
            Where a System Process Xmip owns writes its declaration: what
            XMIP_PROCESS_DIRECTORY names, else xmip/process under the system's
            temporary directory — the rule the processes themselves follow.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    [string] $named = $env:XMIP_PROCESS_DIRECTORY

    if (-not [string]::IsNullOrWhiteSpace($named)) {
        return $named
    }

    return Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath 'xmip' |
        Join-Path -ChildPath 'process'
}

function Get-XmipProcess {
    <#
        .SYNOPSIS
            Lists every System Process Xmip owns, with the name, the location
            and the purpose each declared.

        .DESCRIPTION
            Every System Process Xmip owns is named xmip-<what> (ADR-0053), so
            the operating system's list is the list:

                Get-Process Xmip-* | Stop-Process -Force

            stops them all. This says what each one is for before you do. A
            process declares three things where it starts — its name, its
            location, and its purpose, test or runtime — to one file named for
            it and its pid, and takes the file away where it ends. A process
            that was killed leaves its file behind; this drops it.

            A process that declared nothing is still listed, by its name, with
            Declared false: the name is the rule, the declaration the courtesy.

        .PARAMETER Name
            Only the processes whose name matches, wildcards allowed:
            -Name 'xmip-playground-*' is a roll, its cluster and its nodes.
            Every Xmip process unless said.

        .PARAMETER Purpose
            Only the processes that declared this purpose: Test or Runtime.
            Two values and both are offered, so this is a set rather than a
            pattern (ADR-0055 clause 4).

        .PARAMETER Path
            The directory the declarations are in. Defaults to what
            XMIP_PROCESS_DIRECTORY names, else xmip/process under the system's
            temporary directory.

        .EXAMPLE
            Get-XmipProcess

        .EXAMPLE
            Get-XmipProcess -Purpose Test | Stop-Process -Force

        .EXAMPLE
            Get-XmipProcess -Name 'xmip-playground-node'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [SupportsWildcards()]
        [string] $Name = '*',

        [Parameter()]
        [ValidateSet('Test', 'Runtime')]
        [string] $Purpose,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-XmipProcessDirectory)
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    [hashtable] $declared = Read-XmipProcessDeclaration -Path $Path

    foreach ($process in @(Get-Process -Name 'xmip-*' -ErrorAction SilentlyContinue)) {
        if ($process.ProcessName -notlike $Name) {
            continue
        }

        $said = $declared[$process.Id]
        [string] $stated = if ($null -ne $said) { [string] $said['purpose'] } else { '' }

        if ($PSBoundParameters.ContainsKey('Purpose') -and $stated -ne $Purpose) {
            continue
        }

        # An elevated process shows no start time to a session that is not.
        $started = try { $process.StartTime } catch { $null }

        [PSCustomObject]@{
            PSTypeName = 'Xmip.Process'
            Name       = $process.ProcessName
            Id         = $process.Id
            Purpose    = if ($stated) { (Get-Culture).TextInfo.ToTitleCase($stated) } else { '' }
            Location   = if ($null -ne $said) { [string] $said['location'] } else { '' }
            Started    = $started
            Declared   = $null -ne $said
        }
    }
}

function Read-XmipProcessDeclaration {
    <#
        .SYNOPSIS
            The declarations in a directory, by pid, dropping those whose
            process is gone: a killed process cannot take its own away.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    [hashtable] $byId = @{}

    if (-not (Test-Path -LiteralPath $Path)) {
        return $byId
    }

    Import-Module PSToml -ErrorAction Stop

    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Filter 'xmip-*.toml' -File)) {
        $said = try {
            Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Toml
        }
        catch {
            $null
        }

        [bool] $numbered = $null -ne $said -and $said.Contains('pid')
        [int] $id = if ($numbered) { [int] $said['pid'] } else { 0 }
        $alive = if ($id -gt 0) { Get-Process -Id $id -ErrorAction SilentlyContinue } else { $null }

        if ($null -eq $alive -or $alive.ProcessName -notlike 'xmip-*') {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            continue
        }

        $byId[$id] = $said
    }

    return $byId
}
