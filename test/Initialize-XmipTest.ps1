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
    and writer for a test. Get-XmipTestFloor is a prerequisite's floor as
    prerequisite.toml declares it. New-XmipTestEnvironment is the System
    Tests' cluster file with what this host would give its machines and
    nodes, as files of the test's own; Read-XmipTestEnvironment,
    Get-XmipTestDeployStep and Write-XmipTestInventory are what
    Deploy-XmipEnvironment reads, applies and writes of it.

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

function Get-XmipTestFloor {
    <#
        .SYNOPSIS
        A prerequisite's floor, the minimum prerequisite.toml declares for
        it, read by the module's TOML reader: what a test holds a file's
        stated requirement to, so a raise is written in the manifest alone.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    $prerequisite = & (Get-Module -Name Xmip) {
        Read-XmipToml -Path (Join-Path (Get-XmipRepositoryRoot) 'prerequisite.toml')
    }
    [string] $floor = [string] $prerequisite.prerequisite.$Name.minimum

    if ([string]::IsNullOrEmpty($floor)) {
        throw "prerequisite.toml declares no minimum for $Name"
    }

    return $floor
}

function New-XmipTestEnvironment {
    <#
        .SYNOPSIS
        An environment as Deploy-XmipEnvironment reads it, with no host: the
        System Tests' cluster file, read by the module's TOML reader, and the
        host facts its machines and nodes need given as files of the test's
        own under -Folder, so what the command makes of it is held with no
        hypervisor, image, authority, build or package. Answers Content,
        the file read; File, a copy of it under -Folder; Facts; Technology;
        Hypervisor; and Folder.

        .DESCRIPTION
        -Linux makes every machine AlmaLinux and names no domain controller
        and no gateway, as a Linux host's environment is until it makes
        Windows machines (ADR-0015, amendment 2026-11-25). -Hypervisor is
        hyperv unless given, libvirt with -Linux.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Folder,

        [Parameter()]
        [string] $Technology = 'msdsc',

        [Parameter()]
        [string] $Hypervisor = '',

        [Parameter()]
        [switch] $Linux
    )

    New-Item -Path $Folder -ItemType Directory -Force | Out-Null
    [string] $source = Join-Path $script:Root 'test/core/system-test/configuration/cluster.xmip'
    $content = & (Get-Module -Name Xmip) { param($Path) Read-XmipToml -Path $Path } $source
    if ($Linux) {
        $environment = $content['environment']
        $environment.Remove('domain_controller')
        $environment.Remove('gateway')
        $environment['machine']['os'] = 'AlmaLinux10'
        $environment['machine'].Remove('dynamic_memory')
        foreach ($name in @($environment['machines'].Keys)) {
            $environment['machines'][$name]['os'] = 'AlmaLinux10'
            $environment['machines'][$name].Remove('dynamic_memory')
        }
        $Hypervisor = if ($Hypervisor) { $Hypervisor } else { 'libvirt' }
    }
    $Hypervisor = if ($Hypervisor) { $Hypervisor } else { 'hyperv' }
    foreach ($each in 'xmip-service', 'xmip.rpm', 'xmip.zip', 'pwsh.tar.gz', 'dsc.tar.gz',
        'pwsh.zip', 'dsc.zip', 'image.iso', 'xmip-system-test-external',
        'xmip-system-test-external.exe') {
        Set-Content -LiteralPath (Join-Path $Folder $each) -Value $each
    }
    # The file as changed, so a command reading it reads what the test reads.
    [string] $file = Join-Path $Folder 'cluster.xmip'
    & (Get-Module -Name Xmip) { param($Path, $Value) Write-XmipToml -Path $Path -Value $Value } (
        $file) $content
    [hashtable] $images = @{}
    foreach ($os in @($content['environment']['images'].Keys)) {
        $images[$os] = Join-Path $Folder 'image.iso'
    }
    [hashtable] $facts = @{
        Network = '10.77.0.0/24'
        Root = Join-Path $Folder 'disks'
        Uplink = 'Uplink'
        WindowsHost = '127.0.0.1'
        Operators = @('CN=tester')
        LinuxAccount = 'account'
        Authority = Join-Path $Folder 'state/authority'
        Identity = Join-Path $Folder 'state/identity'
        Operator = Join-Path $Folder 'state/operator'
        Secret = Join-Path $Folder 'state/secret.xml'
        Images = $images
        Tools = @{
            Linux = @{
                pwsh = @{ path = Join-Path $Folder 'pwsh.tar.gz'; sha256 = 'ab' }
                dsc = @{ path = Join-Path $Folder 'dsc.tar.gz'; sha256 = 'cd' }
            }
            Windows = @{
                pwsh = @{ path = Join-Path $Folder 'pwsh.zip'; sha256 = 'ef' }
                dsc = @{ path = Join-Path $Folder 'dsc.zip'; sha256 = '01' }
            }
        }
        Packages = @{
            Linux = @{ path = Join-Path $Folder 'xmip.rpm' }
            Windows = @{ path = Join-Path $Folder 'xmip.zip' }
        }
        Programs = @{
            Linux = @{ path = Join-Path $Folder 'xmip-system-test-external'
                file = 'xmip-system-test-external' }
            Windows = @{ path = Join-Path $Folder 'xmip-system-test-external.exe'
                file = 'xmip-system-test-external.exe' }
        }
        Slicer = Join-Path $Folder 'xmip-service'
        Hashes = @{}
        Given = @{}
    }
    return @{ Content = $content; File = $file; Facts = $facts; Technology = $Technology
        Hypervisor = $Hypervisor; Folder = $Folder }
}

function Read-XmipTestEnvironment {
    <#
        .SYNOPSIS
        The environment New-XmipTestEnvironment made, as
        Get-XmipDeployEnvironment reads it, its run folder -Run.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Environment,

        [Parameter(Mandatory = $true)]
        [string] $Run
    )

    [string] $cluster = (Get-XmipTestCluster).Name
    & (Get-Module -Name Xmip) {
        param($Environment, $Estate, $Run, $Cluster)
        [hashtable] $reading = @{ Cluster = $Environment.Content; Name = $Cluster
            File = $Environment.File; Technology = $Environment.Technology
            Hypervisor = $Environment.Hypervisor; Facts = $Environment.Facts; Estate = $Estate
            Run = $Run }
        Get-XmipDeployEnvironment @reading
    } $Environment $script:Root $Run $cluster
}

function Get-XmipTestDeployStep {
    <#
        .SYNOPSIS
        Microsoft DSC's steps for an environment as Deploy-XmipEnvironment
        applies them: the module's own reading of New-XmipTestEnvironment's
        and its steps, the private state a stand-in naming no file.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Environment,

        [Parameter(Mandatory = $true)]
        [string] $Run
    )

    [hashtable] $read = Read-XmipTestEnvironment -Environment $Environment -Run $Run
    & (Get-Module -Name Xmip) {
        param($Read, $Estate, $Run)
        [hashtable] $state = @{ Folder = $Run; Key = 'key'; KnownHosts = 'known_hosts'
            HostKey = @{} }
        Get-XmipDeployStep -Read $Read -State $state -Estate $Estate
    } $read $script:Root $Run
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
        [hashtable] $Environment,

        [Parameter(Mandatory = $true)]
        [string] $Run
    )

    [hashtable] $read = Read-XmipTestEnvironment -Environment $Environment -Run $Run
    & (Get-Module -Name Xmip) {
        param($Read, $Estate, $Run)
        [hashtable] $state = @{ Folder = $Run; Key = 'key'; KnownHosts = 'known_hosts'
            HostKey = @{} }
        Write-XmipDeployInventory -Read $Read -State $state -Estate $Estate -Run $Run
    } $read $script:Root $Run
}
