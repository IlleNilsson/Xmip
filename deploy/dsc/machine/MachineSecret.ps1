#requires -PSEdition Core
#requires -Version 7.7.0
# The Windows machines' Administrator secret, as every template reads it: a
# file Export-Clixml wrote on Windows, its password encrypted for the account
# that wrote it by Windows' Data Protection API. Off Windows Export-Clixml
# keeps the password as plain text, a Unicode character array
# (https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/export-clixml),
# so such a file is refused wherever it is read, and a Windows one cannot be
# read off Windows. One home for both technologies: Microsoft DSC's resources
# and Ansible's role, through machine.ps1, dot-source it.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# What every password the Data Protection API encrypted begins with: its blob's
# version, 1, and its provider, {df9d8cd0-1501-11d1-8c7a-00c04fc297eb}.
$script:MachineProtectedPrefix = '01000000d08c9ddf0115d1118c7a00c04fc297eb'

function Read-MachineSecret {
    <#
    .SYNOPSIS
    The Administrator secret at -Path, as a PSCredential. Refused where its
    password is not encrypted, or where it is read off Windows, which cannot
    decrypt it.
    #>
    [CmdletBinding()]
    [OutputType([pscredential])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [xml] $file = Get-Content -LiteralPath $Path -Raw
    [Xml.XmlNamespaceManager] $space = [Xml.XmlNamespaceManager]::new($file.NameTable)
    $space.AddNamespace('ps', 'http://schemas.microsoft.com/powershell/2004/04')
    [Xml.XmlNode] $password = $file.SelectSingleNode('//ps:SS[@N="Password"]', $space)
    [bool] $protected = $null -ne $password -and
        $password.InnerText.ToLowerInvariant().StartsWith($script:MachineProtectedPrefix)
    if (-not $protected) {
        throw ("REFUSED: $Path keeps its password unencrypted. Export-Clixml encrypts it " +
            'only on Windows; write the secret file there, as the account that runs the ' +
            'deployment (deploy/dsc/README.md).')
    }
    if (-not $IsWindows) {
        throw ("REFUSED: $Path is encrypted for a Windows account, and only Windows reads " +
            'it: a Windows machine''s answer and its WinRM logon are made on a Windows host ' +
            '(deploy/dsc/README.md).')
    }
    return Import-Clixml -LiteralPath $Path
}
