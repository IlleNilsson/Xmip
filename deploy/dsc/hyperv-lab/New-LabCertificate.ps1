#requires -PSEdition Core
#requires -Version 7.6.5
using namespace System.Security.Cryptography
using namespace System.Security.Cryptography.X509Certificates
<#
.SYNOPSIS
Makes the lab's TLS files for PostgreSQL: an authority, and a certificate and
key for each PostgreSQL machine, as PEM in lab.json's PostgreSql.Tls paths.
.DESCRIPTION
Xmip obtains no certificate; certificates are files an operator supplies
(doc/architecture/estate-map.md, certificate-provisioning). This makes the
lab's own with .NET alone: an ECDSA P-256 authority valid for a year, and per
PostgreSQL machine <Name>.crt for <name>.<DomainName> and <Name>.key. The
authority's key is never written, so nothing more can be issued under it; run
again with -Force to make a new authority and every certificate anew. Writes
nothing where the files exist, unless -Force.
.PARAMETER ConfigPath
The lab's lab.json.
.PARAMETER Force
Replaces the authority and every certificate.
.EXAMPLE
./New-LabCertificate.ps1 -ConfigPath D:\Repos\Xmip\.local-work\hyperv-lab\lab.json
#>
[CmdletBinding(SupportsShouldProcess = $true)]
[OutputType([void])]
param(
    [Parameter(Mandatory = $true)]
    [string] $ConfigPath,

    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'LabHost.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath 'LabLinux.ps1')

function New-LabCertificateRequest {
    [CmdletBinding()]
    [OutputType([CertificateRequest])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Subject,

        [Parameter(Mandatory = $true)]
        [ECDsa] $Key
    )

    return [CertificateRequest]::new($Subject, $Key, [HashAlgorithmName]::SHA256)
}

function New-LabServerCertificate {
    <#
    .SYNOPSIS
    One server's certificate for its DNS name, issued by the authority; writes
    <Base>.crt and <Base>.key.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [X509Certificate2] $Authority,

        [Parameter(Mandatory = $true)]
        [string] $DnsName,

        [Parameter(Mandatory = $true)]
        [string] $Base
    )

    [DateTimeOffset] $now = [DateTimeOffset]::UtcNow
    [ECDsa] $key = [ECDsa]::Create([ECCurve+NamedCurves]::nistP256)
    try {
        [CertificateRequest] $request = New-LabCertificateRequest -Subject "CN=$DnsName" -Key $key
        [SubjectAlternativeNameBuilder] $alternative = [SubjectAlternativeNameBuilder]::new()
        $alternative.AddDnsName($DnsName)
        $request.CertificateExtensions.Add($alternative.Build())
        [OidCollection] $usage = [OidCollection]::new()
        $usage.Add([Oid]::new('1.3.6.1.5.5.7.3.1')) | Out-Null
        $request.CertificateExtensions.Add([X509EnhancedKeyUsageExtension]::new($usage, $false))
        [byte[]] $serial = [RandomNumberGenerator]::GetBytes(16)
        $serial[0] = $serial[0] -band 0x7F
        [X509Certificate2] $issued = $request.Create($Authority, $now.AddMinutes(-5),
            $Authority.NotAfter, $serial)
        [IO.File]::WriteAllText("$Base.crt", $issued.ExportCertificatePem() + "`n")
        [IO.File]::WriteAllText("$Base.key", $key.ExportPkcs8PrivateKeyPem() + "`n")
    }
    finally {
        $key.Dispose()
    }
}

[hashtable] $lab = Read-LabConfiguration -Path $ConfigPath
[string] $directory = $lab.PostgreSql.Tls.Directory
[string] $authorityPath = $lab.PostgreSql.Tls.Authority
[object[]] $servers = @($lab.Machines | Where-Object Role -eq 'PostgreSql')
[string[]] $files = @($authorityPath) + @($servers | ForEach-Object {
    Join-Path -Path $directory -ChildPath "$($_.Name).crt"
    Join-Path -Path $directory -ChildPath "$($_.Name).key"
})
if (-not $Force -and @($files | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0) {
    [string] $kept = "OK: the lab's TLS files exist; -Force replaces them."
    Write-Information -MessageData $kept -InformationAction Continue
    return
}
if (-not $PSCmdlet.ShouldProcess($directory, 'Write the lab authority and server certificates')) {
    return
}
foreach ($folder in @($directory, (Split-Path -Path $authorityPath -Parent))) {
    New-Item -Path $folder -ItemType Directory -Force | Out-Null
}
[DateTimeOffset] $now = [DateTimeOffset]::UtcNow
[ECDsa] $authorityKey = [ECDsa]::Create([ECCurve+NamedCurves]::nistP256)
try {
    [string] $subject = "CN=$($lab.LabId) authority"
    [CertificateRequest] $root = New-LabCertificateRequest -Subject $subject -Key $authorityKey
    $root.CertificateExtensions.Add([X509BasicConstraintsExtension]::new($true, $true, 0, $true))
    $root.CertificateExtensions.Add([X509KeyUsageExtension]::new('KeyCertSign, CrlSign', $true))
    [X509Certificate2] $authority = $root.CreateSelfSigned($now.AddMinutes(-5), $now.AddYears(1))
    [IO.File]::WriteAllText($authorityPath, $authority.ExportCertificatePem() + "`n")
    foreach ($server in $servers) {
        [string] $name = "$(Get-LabLinuxHostName -Machine $server).$($lab.DomainName)"
        [string] $base = Join-Path -Path $directory -ChildPath $server.Name
        New-LabServerCertificate -Authority $authority -DnsName $name -Base $base
        Write-Information -MessageData "OK: $base.crt for $name" -InformationAction Continue
    }
}
finally {
    $authorityKey.Dispose()
}
