#requires -Version 7.6.5

Set-StrictMode -Version Latest

# The operator module this session loaded for the estate's own use, once.
[System.Management.Automation.PSModuleInfo] $script:XmipOperatorModule = $null

function Import-XmipOperatorModule {
    <#
        .SYNOPSIS
            Loads the operator module, Xmip.PowerShell, whose Xmip.Surface
            this module calls for every rule it would otherwise write again.

        .DESCRIPTION
            Code is placed once and everything else uses it (CONTRIBUTING, the
            owner, 2026-09-24). A node's declared capability, a published
            snapshot and the worst leaf are Xmip.Surface's, which calls the
            runtime's own rules (xmip_operate.h section 7), so this module
            reads them through the operator module rather than keeping a copy.

            An operator module already in the session is used as it is.
            Otherwise the project is built into a directory of this session's
            own and its binary module imported from there — never from the
            project's bin/, which a loaded module would lock against the next
            build (Test-XmipDotnetModule's reason, 2026-09-03). The prompt
            integration is not loaded: only the assemblies are wanted here.
            Nothing is loaded before a command needs it, so a bare machine
            still imports this module and asks what it is missing.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if ($null -ne $script:XmipOperatorModule -or $null -ne (Get-Module -Name 'Xmip.PowerShell')) {
        return
    }

    [string] $source = 'module/core/operation/powershell/src/Xmip.PowerShell'
    [string] $project = Join-Path -Path (Get-XmipRepositoryRoot) -ChildPath (
        "$source/Xmip.PowerShell.csproj")

    if (-not (Get-Command -Name 'dotnet' -ErrorAction SilentlyContinue)) {
        throw ('Xmip reads capabilities and snapshots through the operator module, which ' +
            'needs dotnet to build: Install-XmipPrerequisite -Role developer -Install.')
    }

    [string] $stamp = [System.Guid]::NewGuid().ToString('n').Substring(0, 8)
    [string] $output = Join-Path ([System.IO.Path]::GetTempPath()) "xmip-operator-$stamp"
    [string[]] $said = @(& dotnet build $project --output $output --verbosity quiet --nologo 2>&1)

    if ($LASTEXITCODE -ne 0) {
        throw ("The operator module did not build, and Xmip reads capabilities and " +
            "snapshots through it. Run: dotnet build $project`n$($said -join "`n")")
    }

    [string] $binary = Join-Path -Path $output -ChildPath 'Xmip.PowerShell.dll'
    $script:XmipOperatorModule = Import-Module -Name $binary -PassThru -ErrorAction Stop
}
