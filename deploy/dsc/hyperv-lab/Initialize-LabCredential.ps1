#requires -PSEdition Core
#requires -Version 7.6.5
<#
.SYNOPSIS
Creates a host-user-bound DPAPI credential bundle for this disposable lab.
.DESCRIPTION
The local account must exist in both prepared images. Its password becomes the
new domain's Administrator password. Supply distinct DSRM and PostgreSQL passwords.
Run DSC as the same Windows user on the same host. No password enters DSC JSON.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
[OutputType([void])]
param(
    [Parameter(Mandatory = $true)]
    [string] $Path,

    [Parameter(Mandatory = $true)]
    [pscredential] $LocalAdministrator,

    [Parameter(Mandatory = $true)]
    [securestring] $DsrmPassword,

    [Parameter(Mandatory = $true)]
    [securestring] $PostgreSqlPassword
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'DPAPI lab credentials require a Windows Hyper-V host.'
}
if ($LocalAdministrator.UserName -ne 'Administrator') {
    throw 'Use the enabled built-in Administrator account in both base images.'
}
if ($PSCmdlet.ShouldProcess($Path, 'Write encrypted lab credentials')) {
    [string] $directory = Split-Path -Path $Path -Parent
    New-Item -Path $directory -ItemType Directory -Force | Out-Null
    [hashtable] $bundle = @{
        LocalAdministrator = $LocalAdministrator
        DsrmPassword = $DsrmPassword
        PostgreSqlPassword = $PostgreSqlPassword
    }
    $bundle | Export-Clixml -LiteralPath $Path
    Write-Information -MessageData "OK: encrypted credentials saved to $Path" -InformationAction Continue
}
