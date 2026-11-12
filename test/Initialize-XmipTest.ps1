#requires -PSEdition Core
#requires -Version 7.7.0

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
    takes a cluster's or a node's name from (ADR-0056, amendment 2026-10-03),
    and Read-XmipTestYaml and Write-XmipTestYaml, the module's YAML reader
    and writer for a test. Read-XmipTestEnvironment and
    Get-XmipTestDeployStep are an environment file's example with what its
    nodes need given, and Microsoft DSC's steps for it, as
    Deploy-XmipEnvironment reads and applies it.

    Not a test file: Pester is told its extension, .Test.ps1, and this is not
    one.

    Style: doc/governance/powershell-style.md
#>

$script:Root = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

Get-Module -Name Xmip -All | Remove-Module -Force -ErrorAction SilentlyContinue
Import-Module -Name (Join-Path -Path $script:Root -ChildPath 'Xmip/Xmip.psd1') -Force

function Read-XmipTestYaml {
    <#
        .SYNOPSIS
        A YAML file read by the module's one reader (Read-XmipYaml.ps1).
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    return (& (Get-Module -Name Xmip) { param($Path) Read-XmipYaml -Path $Path } $Path)
}

function Write-XmipTestYaml {
    <#
        .SYNOPSIS
        A YAML file written by the module's one writer (Read-XmipYaml.ps1).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Value
    )

    & (Get-Module -Name Xmip) {
        param($Path, $Value)
        Write-XmipYaml -Path $Path -Value $Value
    } $Path $Value
}

function Get-XmipTestCluster {
    <#
        .SYNOPSIS
        The test cluster: its file, its name, its nodes in ordinal order and
        its scope.

        .DESCRIPTION
        What the Rust tests read through configure's fixture and the .NET
        tests through TestCluster: the file XMIP_TEST_CLUSTER names, else the
        estate's test/cluster.xmip. A test names a node by its place here, never
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

function Read-XmipTestEnvironment {
    <#
        .SYNOPSIS
        An environment file (deploy/dsc/*.example.toml), read by the
        module's TOML reader, with every value its machines and nodes need
        given as files of the test's own under -Folder, so what
        Deploy-XmipEnvironment makes of it is held with no authority, build
        or package. -Technology sets technology where given.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Folder,

        [Parameter()]
        [string] $Technology = ''
    )

    foreach ($each in 'authority', 'identity') {
        New-Item -Path (Join-Path $Folder $each) -ItemType Directory -Force | Out-Null
    }
    foreach ($each in 'slicer', 'xmip.rpm', 'xmip.msi', 'pwsh.tar.gz', 'dsc.tar.gz',
        'secret.xml') {
        Set-Content -LiteralPath (Join-Path $Folder $each) -Value $each
    }
    $environment = & (Get-Module -Name Xmip) { param($Path) Read-XmipToml -Path $Path } $Path
    $environment['linux_account'] = 'account'
    $environment['secret'] = Join-Path $Folder 'secret.xml'
    $environment['slicer'] = Join-Path $Folder 'slicer'
    $environment['authority'] = Join-Path $Folder 'authority'
    $environment['identity'] = Join-Path $Folder 'identity'
    $environment['host'] = '127.0.0.1'
    $environment['packages'] = @{
        Linux = @{ path = Join-Path $Folder 'xmip.rpm' }
        Windows = @{ path = Join-Path $Folder 'xmip.msi' }
    }
    $environment['tools'] = @{
        Linux = @{
            pwsh = @{ path = Join-Path $Folder 'pwsh.tar.gz'; sha256 = 'AB' }
            dsc = @{ path = Join-Path $Folder 'dsc.tar.gz'; sha256 = 'CD' }
        }
    }
    if ($Technology) {
        $environment['technology'] = $Technology
    }
    return $environment
}

function Get-XmipTestDeployStep {
    <#
        .SYNOPSIS
        Microsoft DSC's steps for an environment as Deploy-XmipEnvironment
        applies them: the module's own reading of the file and its steps,
        the private state a stand-in naming no file.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Environment,

        [Parameter(Mandatory = $true)]
        [string] $Run
    )

    & (Get-Module -Name Xmip) {
        param($Environment, $Estate, $Run)
        [hashtable] $read = Get-XmipDeployEnvironment -Environment $Environment -Estate (
            $Estate) -Run $Run
        [hashtable] $state = @{ Folder = $Run; Key = 'key'; KnownHosts = 'known_hosts'
            HostKey = @{} }
        Get-XmipDeployStep -Read $read -State $state -Estate $Estate
    } $Environment $script:Root $Run
}

function Write-XmipTestInventory {
    <#
        .SYNOPSIS
        Ansible's inventory for an environment as Deploy-XmipEnvironment
        writes it into -Run, and its path; the private state a stand-in
        naming no file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Environment,

        [Parameter(Mandatory = $true)]
        [string] $Run
    )

    & (Get-Module -Name Xmip) {
        param($Environment, $Estate, $Run)
        [hashtable] $read = Get-XmipDeployEnvironment -Environment $Environment -Estate (
            $Estate) -Run $Run
        [hashtable] $state = @{ Folder = $Run; Key = 'key'; KnownHosts = 'known_hosts'
            HostKey = @{} }
        Write-XmipDeployInventory -Read $read -State $state -Estate $Estate -Run $Run
    } $Environment $script:Root $Run
}
