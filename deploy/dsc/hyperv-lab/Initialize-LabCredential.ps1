#requires -PSEdition Core
#requires -Version 7.6.5
<#
.SYNOPSIS
Creates a host-user-bound DPAPI credential bundle and the SSH key for this
disposable lab.
.DESCRIPTION
The local account must exist in both prepared Windows images. Its password
becomes the new domain's Administrator password. Supply a distinct DSRM
password, the password of xmip_storage, the login Xmip Storage connects to
PostgreSQL as, and of xmip_replication, the login the standby streams with;
each database password has 14 or more characters. Run DSC as the same Windows
user on the same host. No password enters DSC JSON.

The SSH key, ed25519, is what cloud-init places on every Linux guest and the
only way into them; it is made once, beside the bundle, and kept.
.PARAMETER Path
The credential bundle, lab.json's CredentialPath.
.PARAMETER SshKeyPath
The SSH private key, lab.json's SshKeyPath; the public key is beside it as .pub.
.EXAMPLE
$secret = @{
    Path = 'D:\Repos\Xmip\.local-work\hyperv-lab\credential.xml'
    SshKeyPath = 'D:\Repos\Xmip\.local-work\hyperv-lab\ssh\xmip-lab'
    LocalAdministrator = Get-Credential -UserName Administrator
    DsrmPassword = Read-Host -Prompt 'DSRM' -AsSecureString
    StoragePassword = Read-Host -Prompt 'xmip_storage' -AsSecureString
    ReplicationPassword = Read-Host -Prompt 'xmip_replication' -AsSecureString
}
./Initialize-LabCredential.ps1 @secret
#>
[CmdletBinding(SupportsShouldProcess = $true)]
[OutputType([void])]
param(
    [Parameter(Mandatory = $true)]
    [string] $Path,

    [Parameter(Mandatory = $true)]
    [string] $SshKeyPath,

    [Parameter(Mandatory = $true)]
    [pscredential] $LocalAdministrator,

    [Parameter(Mandatory = $true)]
    [securestring] $DsrmPassword,

    [Parameter(Mandatory = $true)]
    [securestring] $StoragePassword,

    [Parameter(Mandatory = $true)]
    [securestring] $ReplicationPassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'DPAPI lab credentials require a Windows Hyper-V host.'
}
if ($LocalAdministrator.UserName -ne 'Administrator') {
    throw 'Use the enabled built-in Administrator account in both base images.'
}
foreach ($password in @($StoragePassword, $ReplicationPassword)) {
    if ($password.Length -lt 14) {
        throw 'Each lab database password has 14 or more characters.'
    }
}
if ($PSCmdlet.ShouldProcess($Path, 'Write encrypted lab credentials')) {
    [string] $directory = Split-Path -Path $Path -Parent
    New-Item -Path $directory -ItemType Directory -Force | Out-Null
    [hashtable] $bundle = @{
        LocalAdministrator = $LocalAdministrator
        DsrmPassword = $DsrmPassword
        StoragePassword = $StoragePassword
        ReplicationPassword = $ReplicationPassword
    }
    $bundle | Export-Clixml -LiteralPath $Path
    [string] $saved = "OK: encrypted credentials saved to $Path"
    Write-Information -MessageData $saved -InformationAction Continue
}
if (-not (Test-Path -LiteralPath $SshKeyPath -PathType Leaf) -and
    $PSCmdlet.ShouldProcess($SshKeyPath, 'Create the lab SSH key')) {
    New-Item -Path (Split-Path -Path $SshKeyPath -Parent) -ItemType Directory -Force | Out-Null
    # No passphrase: DSC runs unattended. ssh-keygen restricts the file to this user.
    & ssh-keygen -q -t ed25519 -N '' -C 'xmip-lab' -f $SshKeyPath
    if ($LASTEXITCODE -ne 0) {
        throw 'ssh-keygen could not create the lab SSH key.'
    }
    Write-Information -MessageData "OK: SSH key created at $SshKeyPath" -InformationAction Continue
}
