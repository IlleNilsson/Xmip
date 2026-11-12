#requires -PSEdition Core
#requires -Version 7.7.0

<#
    deploy/dsc/machine without a hypervisor: what a machine is, and on
    libvirt each step of its installation, for both technologies.

    - The kickstart gives an AlmaLinux machine the host key made for it,
      mode 0600; machine.ps1 answers Ansible the definition Microsoft DSC's
      resources hand libvirt.
    - The answer medium, which holds the machine's keys or password, is
      written in a folder made for it alone, named at random and, off
      Windows, 0700, and the folder is removed.
    - A volume is trusted only whole: made sparse and uploaded, and one an
      upload that stopped left short is deleted and uploaded again.
    - The machine is recorded installed only once its drives are empty and
      its answer medium is gone, and the record names the technology that
      made it: the other one is refused.
    - The Windows machines' secret file is read only where its password is
      encrypted, by Windows: off Windows Export-Clixml keeps it as plain
      text.

    virsh is a stub here; the machines themselves are proved by running
    Deploy-XmipEnvironment (deploy/dsc/README.md).

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Machine = Join-Path $script:Root 'deploy/dsc/machine'
    . (Join-Path $script:Machine 'LibvirtInstallation.ps1')

    function New-Machine {
        param([string] $Technology = 'msdsc')

        return @{
            name = 'XMIP-IN01'; environment = 'xmip'; technology = $Technology
            address = '10.77.0.61'; memoryGB = 4; cpu = 2; diskGB = 32; pool = 'xmip'
            network = @{ name = 'xmip'; gateway = '10.77.0.1'; prefixLength = 24 }
            image = @{ family = 'Linux'; path = 'image.iso'
                sha256 = ('90244AC532F67C97' + ('0' * 48)) }
        }
    }
}

Describe 'What a machine is' {
    It 'gives an AlmaLinux machine the host key made for it, mode 0600' {
        [string] $key = "-----BEGIN OPENSSH PRIVATE KEY-----`nAAAA`n" +
            '-----END OPENSSH PRIVATE KEY-----'
        [string] $kickstart = Get-MachineKickstart -Machine ([pscustomobject] @{
                name = 'XMIP-IN01'; domainName = 'xmip.test'; address = '10.77.0.61'
                linuxAccount = 'account'
                network = @{ prefixLength = 24; gateway = '10.77.0.1'; dnsServer = '10.77.0.1' }
            }) -PublicKey 'ssh-ed25519 AAAA' -MacAddress '5254004D003D' -GuestPackage (
            'qemu-guest-agent') -HostKey $key
        [string] $post = $kickstart.Substring($kickstart.IndexOf('%post'))
        $post | Should -Match ([regex]::Escape(
                "cat > /etc/ssh/ssh_host_ed25519_key <<'XMIP-HOST-KEY'`n$key`nXMIP-HOST-KEY"))
        $post | Should -Match 'chmod 0600 /etc/ssh/ssh_host_ed25519_key'
        Get-MachineKickstart -Machine ([pscustomobject] @{
                name = 'X'; domainName = 'd'; address = '10.0.0.1'; linuxAccount = 'a'
                network = @{ prefixLength = 24; gateway = '10.0.0.2'; dnsServer = '10.0.0.2' }
            }) -PublicKey 'ssh-ed25519 AAAA' -MacAddress '525400000001' -GuestPackage 'g' |
            Should -Not -Match 'ssh_host_ed25519_key'
    }

    It 'answers Ansible the network definition Microsoft DSC hands libvirt' {
        [hashtable] $network = @{ name = 'xmip'; bridge = 'virbr-xmip'; gateway = '10.77.0.1'
            prefixLength = 24; machines = @(@{ name = 'XMIP-IN01'; address = '10.77.0.61' })
            names = @(@{ name = 'n'; addresses = @('10.77.0.61') }) }
        [string] $entry = Join-Path $script:Machine 'machine.ps1'
        [string] $asked = ($network | ConvertTo-Json -Depth 5 |
            & pwsh -NoProfile -File $entry -Hypervisor libvirt -Kind Network) -join "`n"
        $asked | Should -Be (Get-LibvirtNetworkDefinition -Instance $network)
    }

    It 'records the machine installed by the technology that made it' {
        (Get-LibvirtMachinePlan -Instance (New-Machine -Technology 'ansible')).metadata.record |
            Should -Be "<machine installed='yes' technology='ansible'/>"
    }
}

Describe 'The answer medium' {
    It 'is written in a folder of its own, named at random and 0700, which is removed' {
        $script:Written = $null
        $script:Folder = @()
        function Invoke-Virsh {
            param([string[]] $Argument, [switch] $Quiet)
            # The image and the disk are there whole; the answer medium is not.
            if ($Argument[0] -eq 'vol-info' -and $Argument[-1] -notlike '*-answer.iso') {
                return "Capacity:       10 bytes`nAllocation:     12 bytes"
            }
            if ($Argument[0] -eq 'domstate') {
                return 'running'
            }
            return $null
        }
        function New-LibvirtAnswerMedium {
            param($Instance, $Path, [switch] $Confirm)
            [string] $folder = Split-Path -Path $Path -Parent
            $script:Written = $Path
            $script:Folder = @($folder, (Test-Path -LiteralPath $folder))
            if (-not $IsWindows) {
                $script:Folder += [IO.File]::GetUnixFileMode($folder)
            }
            Set-Content -LiteralPath $Path -Value 'answer'
        }
        function Add-LibvirtVolume { param($Pool, $Name, $Path) }
        function Invoke-VirshDefinition { param($Command, $Definition) }
        Start-LibvirtMachineInstallation -Instance (New-Machine)
        [string] $folder = $script:Folder[0]
        Split-Path -Path $script:Written -Leaf | Should -Be 'XMIP-IN01-answer.iso'
        Split-Path -Path $folder -Leaf | Should -BeLike 'xmip-answer-*'
        Split-Path -Path $folder -Leaf | Should -Not -Be 'xmip-answer-'
        $script:Folder[1] | Should -BeTrue
        if (-not $IsWindows) {
            $script:Folder[2] | Should -Be ([IO.UnixFileMode] 'UserRead, UserWrite, UserExecute')
        }
        Test-Path -LiteralPath $folder | Should -BeFalse -Because 'it is removed'
    }
}

Describe 'A volume' {
    It 'is trusted only whole: one an upload left short is deleted and uploaded again' {
        $script:Asked = [Collections.Generic.List[string]]::new()
        $script:Allocated = 4
        function Invoke-Virsh {
            param([string[]] $Argument, [switch] $Quiet)
            $script:Asked.Add($Argument -join ' ')
            if ($Argument[0] -eq 'vol-info') {
                return "Capacity:       10 bytes`nAllocation:     $script:Allocated bytes"
            }
        }
        [string] $iso = Join-Path $TestDrive 'image.iso'
        Set-Content -LiteralPath $iso -Value '0123456789' -NoNewline
        Add-LibvirtVolume -Pool 'xmip' -Name 'image-90244ac532f67c97.iso' -Path $iso
        @($script:Asked | Select-Object -Skip 1) | Should -Be @(
            'vol-delete --pool xmip image-90244ac532f67c97.iso'
            'vol-create-as xmip image-90244ac532f67c97.iso 10 --allocation 0 --format raw'
            'vol-upload --pool xmip image-90244ac532f67c97.iso ' + $iso)
        $script:Asked.Clear()
        $script:Allocated = 12
        Add-LibvirtVolume -Pool 'xmip' -Name 'image-90244ac532f67c97.iso' -Path $iso
        @($script:Asked) | Should -Be @('vol-info --bytes --pool xmip image-90244ac532f67c97.iso')
    }
}

Describe 'Its installation completed' {
    BeforeEach {
        $script:Asked = [Collections.Generic.List[string]]::new()
        $script:Drive = '-'
        $script:Answer = $null
        function Invoke-Virsh {
            param([string[]] $Argument, [switch] $Quiet)
            $script:Asked.Add($Argument[0])
            switch ($Argument[0]) {
                'domstate' { return 'running' }
                'domblklist' {
                    return (" Type   Device   Target   Source`n -----`n" +
                        " volume disk     vda      XMIP-IN01.qcow2`n" +
                        " file   cdrom    sdb      -`n" +
                        " volume cdrom    sdc      $script:Drive")
                }
                'vol-info' { return $script:Answer }
            }
        }
    }

    It 'records the machine installed once its drives are empty and its answer medium gone' {
        Complete-LibvirtMachineInstallation -Instance (New-Machine)
        $script:Asked[-1] | Should -Be 'metadata'
    }

    It 'refuses a drive that still holds a medium, before the record' {
        $script:Drive = 'XMIP-IN01-answer.iso'
        { Complete-LibvirtMachineInstallation -Instance (New-Machine) } |
            Should -Throw 'REFUSED: XMIP-IN01: its drive sdc still holds a medium.'
        $script:Asked | Should -Not -Contain 'metadata'
    }

    It 'refuses an answer medium still in the pool, before the record' {
        $script:Answer = 'Name: XMIP-IN01-answer.iso'
        { Complete-LibvirtMachineInstallation -Instance (New-Machine) } |
            Should -Throw 'REFUSED: XMIP-IN01: its answer medium XMIP-IN01-answer.iso is still*'
        $script:Asked | Should -Not -Contain 'metadata'
    }
}

Describe 'The record' {
    It 'refuses a machine another technology made: an environment is never a mix' {
        function Invoke-Virsh {
            param([string[]] $Argument, [switch] $Quiet)
            switch ($Argument[0]) {
                'domstate' { return 'running' }
                'metadata' { return '<machine installed="yes" technology="msdsc"/>' }
            }
        }
        (Get-LibvirtMachineRecord -Instance (New-Machine)).installed | Should -BeTrue
        { Get-LibvirtMachineRecord -Instance (New-Machine -Technology 'ansible') } |
            Should -Throw "REFUSED: XMIP-IN01 was made by 'msdsc', not ansible*never a mix*"
    }

    It 'answers a machine not defined yet as neither defined nor installed' {
        function Invoke-Virsh { param([string[]] $Argument, [switch] $Quiet) }
        [hashtable] $record = Get-LibvirtMachineRecord -Instance (New-Machine)
        "$($record.defined) $($record.installed)" | Should -Be 'False False'
    }
}

Describe 'The Windows machines'' secret' {
    It 'refuses a file whose password Export-Clixml kept as plain text, as it does off Windows' {
        # PowerShell 7 on Linux writes the password's UTF-16 bytes as hex: "pw".
        [string] $path = Join-Path $TestDrive 'plain.xml'
        Set-Content -LiteralPath $path -Value @(
            '<Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04">'
            '  <Obj RefId="0"><TN RefId="0"><T>System.Management.Automation.PSCredential</T>'
            '  <T>System.Object</T></TN><Props><S N="UserName">Administrator</S>'
            '  <SS N="Password">70007700</SS></Props></Obj>'
            '</Objs>')
        { Read-MachineSecret -Path $path } |
            Should -Throw 'REFUSED: * keeps its password unencrypted*'
    }

    It 'reads one Windows encrypted, on Windows alone' {
        [string] $path = Join-Path $TestDrive 'secret.xml'
        [securestring] $password = ConvertTo-SecureString -String 'Pa55word' -AsPlainText -Force
        [pscredential]::new('Administrator', $password) | Export-Clixml -LiteralPath $path
        if ($IsWindows) {
            (Read-MachineSecret -Path $path).GetNetworkCredential().Password | Should -Be 'Pa55word'
        }
        else {
            { Read-MachineSecret -Path $path } | Should -Throw 'REFUSED:*'
        }
    }
}
