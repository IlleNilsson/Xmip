#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    What every test file starts from: the estate root and one loaded copy of
    the module.

.DESCRIPTION
    Dot-sourced first in each test file's BeforeAll:

        . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    It sets $script:Root to the estate root, resolved, and imports
    Xmip/Xmip.psd1 after removing every copy already loaded. Pester runs the
    whole test/ directory in one session and several files import the module;
    two loaded copies make InModuleScope throw "Multiple script or manifest
    modules named 'Xmip' are currently loaded", which reads as a broken test.

    Not a test file: Pester is told its extension, .Test.ps1, and this is not
    one.

    Style: doc/governance/powershell-style.md
#>

$script:Root = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

Get-Module -Name Xmip -All | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module -Name (Join-Path -Path $script:Root -ChildPath 'Xmip/Xmip.psd1') -Force
