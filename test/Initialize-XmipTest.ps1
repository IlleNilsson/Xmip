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

    It also defines Get-XmipTestCluster, the one place a PowerShell test
    takes a cluster's or a node's name from (ADR-0056, amendment 2026-10-03).

    Not a test file: Pester is told its extension, .Test.ps1, and this is not
    one.

    Style: doc/governance/powershell-style.md
#>

$script:Root = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

Get-Module -Name Xmip -All | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module -Name (Join-Path -Path $script:Root -ChildPath 'Xmip/Xmip.psd1') -Force

function Get-XmipTestCluster {
    <#
        .SYNOPSIS
        The test cluster: its file, its name, its nodes in ordinal order and
        its scope.

        .DESCRIPTION
        What the Rust tests read through configure's fixture and the .NET
        tests through TestCluster: the file XMIP_TEST_CLUSTER names, else the
        estate's test/xmip.toml. A test names a node by its place here, never
        by a literal (the owner, 2026-10-03). Throws when the file is not
        there or names no cluster or no node.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # The module's one reading of a cluster's file, the one a run takes its
    # nodes from (Write-XmipTestCluster.ps1), called in its own scope.
    $read = & (Get-Module -Name Xmip) {
        Read-XmipTestCluster -Path (Get-XmipTestClusterPath)
    }

    if ($read.Nodes.Count -eq 0) {
        throw "the test cluster $($read.Path) declares no node"
    }

    return $read
}
