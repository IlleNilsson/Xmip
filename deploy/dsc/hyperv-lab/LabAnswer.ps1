#requires -PSEdition Core
#requires -Version 7.6.5
# The answers an unattended installation reads, one function for each kind:
# Windows Setup's autounattend.xml and Anaconda's kickstart. Each is text and
# nothing else, written by no other function, so a second desired-state
# technology installing the same machines can take the same answers.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The attributes every component of an amd64 answer file carries.
$script:LabUnattendComponent = 'processorArchitecture="amd64" ' +
    'publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"'

function ConvertTo-LabUnattendPassword {
    <#
    .SYNOPSIS
    A password as an answer file holds it with PlainText false: Base64 of the
    UTF-16 password followed by the name of the element that holds it.
    .DESCRIPTION
    This is how Windows lets an answer file avoid plain text. It is an
    encoding, not encryption: whoever reads the file can decode it, so the
    answer medium is ejected and deleted once the guest answers.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [securestring] $Password,

        [Parameter(Mandatory = $true)]
        [string] $Element
    )

    [string] $plain = [pscredential]::new('answer', $Password).GetNetworkCredential().Password
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($plain + $Element))
}

function Get-LabWindowsAnswer {
    <#
    .SYNOPSIS
    The autounattend.xml that installs one Windows machine from its ISO.
    .DESCRIPTION
    A GPT layout on the first disk (EFI, MSR, Windows), the image named by
    lab.json's Edition, the computer name, the built-in Administrator enabled
    with the lab's password, and the out-of-box experience skipped, so the
    guest answers PowerShell Direct as Administrator when Setup is done.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [securestring] $AdministratorPassword
    )

    # Each token stands alone between two tags of the template below.
    [hashtable] $value = @{
        EDITION = $Lab.Images[$Machine.Os].Edition
        COMPUTERNAME = $Machine.Name
        PASSWORD = ConvertTo-LabUnattendPassword -Password $AdministratorPassword -Element (
            'AdministratorPassword')
    }
    [string] $template = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend"
    xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" COMPONENT>
      <SetupUILanguage><UILanguage>en-US</UILanguage></SetupUILanguage>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" COMPONENT>
      <DiskConfiguration>
        <Disk wcm:action="add">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order><Type>EFI</Type><Size>260</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order><Type>MSR</Type><Size>16</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>3</Order><Type>Primary</Type><Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Order>1</Order><PartitionID>1</PartitionID>
              <Format>FAT32</Format><Label>System</Label>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>2</Order><PartitionID>2</PartitionID>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Order>3</Order><PartitionID>3</PartitionID>
              <Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add"><Key>/IMAGE/NAME</Key><Value>EDITION</Value></MetaData>
          </InstallFrom>
          <InstallTo><DiskID>0</DiskID><PartitionID>3</PartitionID></InstallTo>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
        <FullName>Xmip lab</FullName>
        <Organization>Xmip lab</Organization>
      </UserData>
    </component>
  </settings>
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" COMPONENT>
      <ComputerName>COMPUTERNAME</ComputerName>
      <TimeZone>UTC</TimeZone>
    </component>
    <component name="Microsoft-Windows-Deployment" COMPONENT>
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Path>net user Administrator /active:yes</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-International-Core" COMPONENT>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Shell-Setup" COMPONENT>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <AdministratorPassword>
          <Value>PASSWORD</Value>
          <PlainText>false</PlainText>
        </AdministratorPassword>
      </UserAccounts>
    </component>
  </settings>
</unattend>
'@
    [string] $answer = $template.Replace('COMPONENT>', "$script:LabUnattendComponent>")
    foreach ($token in $value.Keys) {
        [string] $text = [Security.SecurityElement]::Escape($value[$token])
        $answer = $answer.Replace(">$token<", ">$text<")
    }
    return $answer -replace "`r`n", "`n"
}

function Get-LabKickstart {
    <#
    .SYNOPSIS
    The ks.cfg that installs one AlmaLinux machine from its DVD.
    .DESCRIPTION
    Installs from the DVD's own repositories, so no network is needed while
    installing: the host name, the static address on the adapter matched by
    the static MAC the lab gives it, the domain controller as DNS server,
    the account xmiplab with the lab's SSH key, no password and sudo without
    one, root locked, sshd and firewalld enabled. LF line endings.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [string] $PublicKey
    )

    [string] $hostName = "$(Get-LabLinuxHostName -Machine $Machine).$($Lab.DomainName)"
    [string] $mac = (Get-LabMacAddress -Address $Machine.Address) -replace '(..)(?!$)', '$1:'
    [string] $dns = ($Lab.Machines | Where-Object Role -eq 'DomainController').Address
    [string] $bits = ('1' * $Lab.Network.PrefixLength).PadRight(32, '0')
    [string] $netmask = (0..3 | ForEach-Object {
        [Convert]::ToByte($bits.Substring($_ * 8, 8), 2)
    }) -join '.'
    [string] $user = $script:LabLinuxUser
    [string[]] $kickstart = @(
        "# The Xmip Hyper-V lab's $($Machine.Name), installed from the DVD."
        'cdrom'
        'text'
        'skipx'
        'firstboot --disable'
        'lang en_US.UTF-8'
        'keyboard --vckeymap=us'
        'timezone Etc/UTC --utc'
        "network --device=$mac --bootproto=static --ip=$($Machine.Address) " +
            "--netmask=$netmask --gateway=$($Lab.Network.Gateway) --nameserver=$dns " +
            "--hostname=$hostName --noipv6 --onboot=yes --activate"
        'rootpw --lock'
        "user --name=$user --groups=wheel --gecos=`"Xmip lab`" --lock"
        "sshkey --username=$user `"$PublicKey`""
        'firewall --enabled --service=ssh'
        'selinux --enforcing'
        'services --enabled=sshd,firewalld'
        'zerombr'
        'clearpart --all --initlabel --disklabel=gpt'
        'autopart --type=lvm --nohome'
        'reboot'
        ''
        '%packages'
        '@^minimal-environment'
        'openssh-server'
        'firewalld'
        'sudo'
        'tar'
        'hyperv-daemons'
        '%end'
        ''
        '%post --erroronfail'
        "echo '$user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$user"
        "chmod 0440 /etc/sudoers.d/$user"
        "echo 'PasswordAuthentication no' > /etc/ssh/sshd_config.d/40-xmip-lab.conf"
        '%end'
    )
    return ($kickstart -join "`n") + "`n"
}

function Get-LabAnswerMedium {
    <#
    .SYNOPSIS
    What one machine's answer medium holds: its volume label and its files.
    .DESCRIPTION
    Windows Setup reads autounattend.xml from the root of any removable
    medium; Anaconda reads ks.cfg from a volume labelled OEMDRV without being
    told to. The Windows answer needs the lab's Administrator password.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [AllowNull()]
        [securestring] $AdministratorPassword
    )

    if ($Machine.Family -eq 'Windows') {
        [hashtable] $windows = @{
            Lab = $Lab
            Machine = $Machine
            AdministratorPassword = $AdministratorPassword
        }
        return @{
            Label = 'XMIPLAB'
            File = [ordered] @{ 'autounattend.xml' = Get-LabWindowsAnswer @windows }
        }
    }
    [hashtable] $linux = @{
        Lab = $Lab
        Machine = $Machine
        PublicKey = Get-LabPublicKey -Lab $Lab
    }
    return @{
        Label = 'OEMDRV'
        File = [ordered] @{ 'ks.cfg' = Get-LabKickstart @linux }
    }
}
