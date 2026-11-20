#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The operator module's assemblies, loaded with it, so a type this module
    names is found on every system.

.DESCRIPTION
    This module names types of the operator module's assemblies itself —
    [Xmip.Surface.ProgramAudit], [Xmip.Surface.ScopeTree],
    [Xmip.Abi.Operate.Counted] and the rest — and PowerShell finds a type
    only among the assemblies loaded. .NET loads one when code first needs
    it: importing the operator module loads Xmip.Surface on Windows as the
    import reads the cmdlets, and on Linux not until a cmdlet runs, so there
    every such name was unknown, and Write-XmipAudit, the first call of
    Build-XmipService, failed (2026-11-20).

    Style: doc/governance/powershell-style.md
#>


function Import-XmipOperatorAssembly {
    <#
        .SYNOPSIS
            Loads the assembly of each project the operator module is built
            from (Get-XmipOperatorModuleKey's sources), from the folder its
            binary was loaded from, where one of that name is not loaded yet:
            .NET refuses a second of the same name.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSModuleInfo] $Module
    )

    [string] $location = $Module.ImplementingAssembly.Location

    if ([string]::IsNullOrEmpty($location)) {
        return
    }

    [string] $folder = Split-Path -Path $location -Parent
    [System.Collections.Generic.HashSet[string]] $loaded =
        [System.Collections.Generic.HashSet[string]]::new()

    foreach ($assembly in [System.AppDomain]::CurrentDomain.GetAssemblies()) {
        $null = $loaded.Add($assembly.GetName().Name)
    }

    foreach ($source in $script:XmipOperatorModuleSource) {
        [string] $name = Split-Path -Path $source -Leaf
        [string] $file = Join-Path -Path $folder -ChildPath "$name.dll"

        if (-not $loaded.Contains($name) -and [System.IO.File]::Exists($file)) {
            $null = [System.Reflection.Assembly]::LoadFrom($file)
        }
    }
}
