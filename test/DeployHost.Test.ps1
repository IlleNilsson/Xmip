#requires -PSEdition Core
#requires -Version 7.7.0

<#
    What a cluster file's [environment] makes, and what this host gives it
    (ADR-0015, amendment 2026-11-25; the owner, 2026-11-25: *I still don't
    get why there is a need for two files?*), without a hypervisor:

    - Resolve-XmipDeployMachine: one virtual machine for each node, each far
      end and each machine of its own, named XMIP-<name>, in the order their
      addresses are given; sized by its own table, else the default, else
      the built-in; given the way out where its node declares online; and
      described in one line by its role, from what the file declares, and its
      operating system, in its image's own words (the owner, 2026-11-25:
      "I want it to state Role and OS type"). Refused: a machine with no
      os, an os no image names, a far end named as a node, a Windows name
      longer than NetBIOS takes.
    - Get-XmipDeployHypervisor: the kind the host makes, Hyper-V on
      Windows and libvirt on Linux; -Hypervisor hyperv for Ansible from WSL
      alone.
    - Get-XmipDeployFreeNetwork: the first private /24 no host prefix
      overlaps.
    - Get-XmipDeployHost: a fact given is taken over one kept, one kept over
      Xmip's own; what is given or chosen is kept, and read back; an image
      and a tool are found by their SHA-256, each read once; the build of
      this tree is named where it is not there.
    - Read-XmipDeployedEnvironment: nothing where no environment of the
      cluster is deployed.

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Cluster = (Get-XmipTestCluster).Name

    # The System Tests' cluster file, as Read-XmipToml reads it.
    function Read-Cluster {
        & (Get-Module -Name Xmip) {
            Read-XmipToml -Path (Join-Path (Get-XmipRepositoryRoot) (
                    'test/core/system-test/configuration/cluster.xmip'))
        }
    }

    # The machines a cluster file's [environment] makes.
    function Resolve-Machine {
        param($Content)

        & (Get-Module -Name Xmip) { param($Content) Resolve-XmipDeployMachine -Cluster $Content } (
            $Content)
    }

    # An estate of the test's own under -Folder: Cargo.toml's version, the
    # build of it under .local-work/package, and prerequisite.toml's
    # archives, each a file whose SHA-256 is its text's.
    function New-Estate {
        param([string] $Folder, [switch] $Built)

        New-Item -Path $Folder -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Folder 'Cargo.toml') -Value (
            "[package]`nname = `"xmip`"`nversion = `"9.9.9`"")
        [string] $package = Join-Path $Folder '.local-work/package/9.9.9'
        if ($Built) {
            foreach ($file in 'xmip-9.9.9-personal-computer-windows-x64.zip',
                'xmip-9.9.9-personal-computer-linux-x64.rpm',
                'modules/windows/order_approval.dll', 'modules/linux/liborder_approval.so',
                'far-end/windows/xmip-system-test-external.exe',
                'far-end/linux/xmip-system-test-external',
                'personal-computer-windows-x64/xmip/bin/xmip-service.exe',
                'personal-computer-linux-x64/xmip/bin/xmip-service') {
                [string] $path = Join-Path $package $file
                New-Item -Path (Split-Path $path) -ItemType Directory -Force | Out-Null
                Set-Content -LiteralPath $path -Value $file
            }
        }
        [string] $images = Join-Path $Folder 'images'
        New-Item -Path $images -ItemType Directory -Force | Out-Null
        [string[]] $lines = @()
        foreach ($tool in 'powershell', 'dsc') {
            $lines += "[prerequisite.$tool.archive]"
            foreach ($family in 'linux', 'windows') {
                [string] $name = "$tool-$family.archive"
                [string] $path = Join-Path $images $name
                Set-Content -LiteralPath $path -Value $name -NoNewline
                [string] $sha = (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
                $lines += "$family = { file = `"$name`", sha256 = `"$sha`" }"
            }
        }
        Set-Content -LiteralPath (Join-Path $Folder 'prerequisite.toml') -Value $lines
        return $images
    }
}

Describe 'The machines a cluster file''s environment makes' {
    BeforeAll {
        $script:Content = Read-Cluster
        [hashtable[]] $script:Machines = @(Resolve-Machine -Content $script:Content)
        $script:Environment = $script:Content['environment']
        [string[]] $script:Nodes = @($script:Content['nodes'].Keys)
        [string[]] $script:FarEnds = @($script:Environment['far_ends']['senders']) +
            @($script:Environment['far_ends']['receivers'])
    }

    It 'makes one for each node, each far end and each machine of its own, in address order' {
        [string[]] $own = @($script:Environment['machines'].Keys | Where-Object {
                $_ -notin $script:Nodes -and $_ -notin $script:FarEnds })
        @($script:Machines | ForEach-Object { $_.name }) |
            Should -Be @($own + $script:FarEnds + $script:Nodes)
        @($script:Machines | ForEach-Object { $_.machine }) |
            Should -Be @($script:Machines | ForEach-Object { "XMIP-$($_.name)" })
        @($script:Machines | Where-Object { $_.kind -eq 'far end' }).Count |
            Should -Be $script:FarEnds.Count
    }

    It 'sizes each by its own table, else the default, key by key' {
        $default = $script:Environment['machine']
        foreach ($machine in $script:Machines) {
            $own = $script:Environment['machines'][$machine.name]
            foreach ($key in 'os', 'cpu', 'memory_gb', 'disk_gb') {
                [object] $expected = if ($null -ne $own -and $own.Contains($key)) { $own[$key] }
                else { $default[$key] }
                $machine[$key] | Should -Be $expected -Because "$($machine.name)'s $key"
            }
        }
    }

    It 'gives the way out only to the machine of a node that declares online' {
        [string[]] $online = @($script:Nodes | Where-Object {
                @($script:Content['nodes'][$_]['capabilities']) -contains 'online' })
        $online | Should -Not -BeNullOrEmpty
        @($script:Machines | Where-Object { $_.online } | ForEach-Object { $_.name }) |
            Should -Be $online
    }

    It 'describes each by its role and operating system, in one line' {
        [char] $dot = [char] 0x00B7
        foreach ($machine in $script:Machines) {
            $machine.description | Should -Match "^\S.* $([regex]::Escape($machine.name)) $dot \S"
            $machine.description | Should -Not -Match "`n"
            [string] $os = $script:Environment['images'][$machine.os]['name']
            $machine.description | Should -BeLike "* $dot $os"
        }
        [hashtable] $storage = @($script:Machines | Where-Object { $_.storage })[0]
        $storage.description | Should -BeLike "Storage node $($storage.name) $dot *"
        [string] $controller = $script:Environment['domain_controller']
        @($script:Machines | Where-Object { $_.name -eq $controller })[0].description |
            Should -BeLike "Domain controller and gateway $controller $dot *"
        [string] $sender = $script:Environment['far_ends']['senders'][0]
        @($script:Machines | Where-Object { $_.name -eq $sender })[0].description |
            Should -BeLike "Sender far end $sender $dot *"
    }

    It 'refuses a machine with no os, and an os no image names' {
        $content = Read-Cluster
        $content['environment']['machine'].Remove('os')
        { Resolve-Machine -Content $content } | Should -Throw '*names no os*'
        $content = Read-Cluster
        $content['environment']['machine']['os'] = 'Nothing'
        { Resolve-Machine -Content $content } | Should -Throw '*runs Nothing, which no*'
    }

    It 'refuses a far end named as a node' {
        $content = Read-Cluster
        $content['environment']['far_ends']['senders'] = @($script:Nodes[0])
        { Resolve-Machine -Content $content } | Should -Throw "*names $($script:Nodes[0]) twice*"
    }

    It 'refuses a Windows machine whose name is longer than a Windows computer''s may be' {
        $content = Read-Cluster
        $content['environment']['machines']['ABCDEFGHIJK'] = [ordered] @{
            os = 'WindowsServer2025' }
        { Resolve-Machine -Content $content } | Should -Throw '*longer than the 15 characters*'
    }
}

Describe 'What this host gives' {
    It 'takes the host''s own kind of virtual machine, and hyperv from WSL for Ansible alone' {
        [string] $own = if ($IsWindows) { 'hyperv' } elseif ($IsLinux) { 'libvirt' } else { '' }
        if (-not $own) {
            { & (Get-Module -Name Xmip) { Get-XmipDeployHypervisor } } |
                Should -Throw '*macOS has neither*'
            return
        }
        & (Get-Module -Name Xmip) { Get-XmipDeployHypervisor } | Should -Be $own
        [string] $other = if ($own -eq 'hyperv') { 'libvirt' } else { 'hyperv' }
        { & (Get-Module -Name Xmip) { param($Other) Get-XmipDeployHypervisor -Hypervisor $Other } (
                $other) } | Should -Throw '*taken only by Ansible from WSL*'
    }

    It 'picks the first private /24 no prefix of the host overlaps' {
        & (Get-Module -Name Xmip) {
            Get-XmipDeployFreeNetwork -Taken @('10.77.0.1/24', '192.168.1.5/24')
        } | Should -Be '10.77.1.0/24'
        & (Get-Module -Name Xmip) {
            Get-XmipDeployFreeNetwork -Taken @('10.77.0.1/23', '10.77.2.9/32')
        } | Should -Be '10.77.3.0/24' -Because 'a /23 holds two, and one address one'
        { & (Get-Module -Name Xmip) { Get-XmipDeployFreeNetwork -Taken @('10.0.0.0/8') } } |
            Should -Throw '*every network of 10.77.0.0/16 overlaps*'
    }

    It 'takes a fact given over one kept, one kept over its own, and keeps what it took' {
        [string] $images = New-Estate -Folder (Join-Path $TestDrive 'kept') -Built
        [string] $estate = Split-Path $images
        $content = Read-Cluster
        [hashtable] $made = @{ Content = $content; Estate = $estate; Images = $images }
        [hashtable] $taken = InModuleScope Xmip -Parameters $made {
            param($Content, $Estate, $Images)
            Mock Get-XmipDeployHostPrefix { @('10.77.0.1/24') }
            Mock Get-XmipDeployDiskRoot { 'disks' }
            Mock Get-XmipDeployHostSwitch { @('one', 'two') }
            Mock Add-XmipDeployImage { $Facts['Images'] = @{}; $Facts['Tools'] = @{} }
            [hashtable[]] $machines = @(Resolve-XmipDeployMachine -Cluster $Content)
            [hashtable] $asked = @{ Cluster = 'X'; Content = $Content; Machines = $machines
                Hypervisor = 'hyperv'; Technology = 'msdsc'; Estate = $Estate
                State = (Join-Path $Estate 'state') }
            [hashtable] $first = Get-XmipDeployHost @asked -Given @{
                Uplink = 'two'; ImageFolder = $Images; Operator = @('CN=another') }
            Write-XmipDeployHost -Folder $Estate -Facts $first
            [hashtable] $kept = Read-XmipDeployHost -Folder $Estate
            [hashtable] $second = Get-XmipDeployHost @asked -Kept $kept -Given @{
                DiskFolder = 'elsewhere' }
            @{ First = $first; Second = $second }
        }
        $taken.First.Network | Should -Be '10.77.1.0/24'
        $taken.First.Uplink | Should -Be 'two'
        $taken.First.Root | Should -Be (Join-Path 'disks' 'Xmip-X')
        $taken.First.Operators | Should -Be @("CN=$([Environment]::UserName)", 'CN=another')
        # Kept, and taken by the next run that gives none; given over kept.
        $taken.Second.Network | Should -Be '10.77.1.0/24'
        $taken.Second.Uplink | Should -Be 'two'
        $taken.Second.ImageFolder | Should -Be $images
        $taken.Second.Operators | Should -Contain 'CN=another'
        $taken.Second.Root | Should -Be (Join-Path 'elsewhere' 'Xmip-X')
    }

    It 'refuses an uplink where the host has several and none is given or kept' {
        [string] $estate = Split-Path (New-Estate -Folder (Join-Path $TestDrive 'uplink') -Built)
        { InModuleScope Xmip -Parameters @{ Content = (Read-Cluster); Estate = $estate } {
                param($Content, $Estate)
                Mock Get-XmipDeployHostPrefix { @() }
                Mock Get-XmipDeployDiskRoot { 'disks' }
                Mock Get-XmipDeployHostSwitch { @('one', 'two') }
                [hashtable[]] $machines = @(Resolve-XmipDeployMachine -Cluster $Content)
                Get-XmipDeployHost -Cluster 'X' -Content $Content -Machines $machines -Hypervisor (
                    'hyperv') -Technology 'msdsc' -Estate $Estate -State $Estate
            } } | Should -Throw '*it has one, two: name one with -Uplink*'
    }

    It 'finds an image and a tool by its SHA-256, reading each file once' {
        [string] $images = New-Estate -Folder (Join-Path $TestDrive 'found') -Built
        [string] $estate = Split-Path $images
        $content = Read-Cluster
        [string] $iso = Join-Path $images 'nested/any-name.iso'
        New-Item -Path (Split-Path $iso) -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath $iso -Value 'an image' -NoNewline
        [string] $sha = (Get-FileHash -LiteralPath $iso).Hash.ToLowerInvariant()
        foreach ($os in @($content['environment']['images'].Keys)) {
            $content['environment']['images'][$os]['sha256'] = $sha.ToUpperInvariant()
        }
        [hashtable] $made = @{ Content = $content; Estate = $estate; Images = $images }
        [hashtable] $found = InModuleScope Xmip -Parameters $made {
            param($Content, $Estate, $Images)
            [hashtable[]] $machines = @(Resolve-XmipDeployMachine -Cluster $Content)
            [hashtable] $facts = @{ ImageFolder = $Images; Hashes = @{} }
            [hashtable] $asked = @{ Facts = $facts; Content = $Content['environment']
                Machines = $machines; Technology = 'msdsc'; Estate = $Estate }
            Add-XmipDeployImage @asked
            Mock Get-FileHash { throw 'read again' }
            Add-XmipDeployImage @asked
            $facts
        }
        @($found.Images.Values | Sort-Object -Unique) | Should -Be @($iso)
        $found.Tools.Linux.pwsh.path | Should -Be (Join-Path $images 'powershell-linux.archive')
        $found.Tools.Windows.dsc.path | Should -Be (Join-Path $images 'dsc-windows.archive')
        $found.Hashes[$iso].sha256 | Should -Be $sha
    }

    It 'refuses an image no file under the folder has the SHA-256 of' {
        [string] $images = New-Estate -Folder (Join-Path $TestDrive 'missing') -Built
        { InModuleScope Xmip -Parameters @{ Content = (Read-Cluster); Images = $images } {
                param($Content, $Images)
                [hashtable[]] $machines = @(Resolve-XmipDeployMachine -Cluster $Content)
                Add-XmipDeployImage -Facts @{ ImageFolder = $Images; Hashes = @{} } -Content (
                    $Content['environment']) -Machines $machines -Technology 'msdsc' -Estate (
                    Split-Path $Images)
            } } | Should -Throw "*no image under $images has the SHA-256*-ImageFolder*"
    }

    It 'names the build that makes what a machine is given where it is not there' {
        [string] $estate = Split-Path (New-Estate -Folder (Join-Path $TestDrive 'unbuilt'))
        { InModuleScope Xmip -Parameters @{ Content = (Read-Cluster); Estate = $estate } {
                param($Content, $Estate)
                [hashtable[]] $machines = @(Resolve-XmipDeployMachine -Cluster $Content)
                Add-XmipDeployBuild -Facts @{} -Content $Content -Machines $machines -Estate (
                    $Estate)
            } } | Should -Throw '*which is not there: Build-XmipService -Site personal-computer*'
        [string] $built = Split-Path (New-Estate -Folder (Join-Path $TestDrive 'built') -Built)
        [hashtable] $facts = InModuleScope Xmip -Parameters @{ Content = (Read-Cluster)
            Estate = $built } {
            param($Content, $Estate)
            [hashtable[]] $machines = @(Resolve-XmipDeployMachine -Cluster $Content)
            [hashtable] $facts = @{}
            Add-XmipDeployBuild -Facts $facts -Content $Content -Machines $machines -Estate $Estate
            $facts
        }
        $facts.Packages.Windows.path |
            Should -BeLike '*xmip-9.9.9-personal-computer-windows-x64.zip'
        $facts.Packages.Linux.modules | Should -BeLike '*modules*linux'
        $facts.Programs.Windows.file | Should -Be 'xmip-system-test-external.exe'
        $facts.Slicer | Should -BeLike '*personal-computer-*-x64*xmip-service*'
    }

    It 'answers nothing where no environment of the cluster is deployed here' {
        InModuleScope Xmip -Parameters @{ Cluster = $script:Cluster } {
            param($Cluster)
            Mock Get-XmipDeployStateFolder { Join-Path $TestDrive 'none' }
            Read-XmipDeployedEnvironment -Cluster $Cluster | Should -BeNullOrEmpty
        }
    }
}
