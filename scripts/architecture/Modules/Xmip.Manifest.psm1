Set-StrictMode -Version Latest

$script:SupportedSchemaMajor = 1
$script:ScriptVersion = [version]'1.0.0'

function Get-XmipScriptVersion {
    [CmdletBinding()]
    param()
    $script:ScriptVersion
}

function Test-XmipManifestCompatibility {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Manifest)

    if (-not $Manifest.schemaVersion) {
        throw 'Manifest schemaVersion is missing.'
    }

    $schemaVersion = [version]$Manifest.schemaVersion
    if ($schemaVersion.Major -ne $script:SupportedSchemaMajor) {
        throw "Unsupported manifest schema major version '$($schemaVersion.Major)'. Supported major version: $script:SupportedSchemaMajor."
    }

    if ($Manifest.minimumScriptVersion) {
        $minimumScriptVersion = [version]$Manifest.minimumScriptVersion
        if ($script:ScriptVersion -lt $minimumScriptVersion) {
            throw "Manifest requires Set-XmipArchitecture.ps1 $minimumScriptVersion or newer. Current script version: $script:ScriptVersion."
        }
    }

    if (-not $Manifest.architectureVersion) {
        Write-Warning 'Manifest architectureVersion is missing. Compatibility is based on schemaVersion only.'
    }

    [pscustomobject]@{
        schemaVersion = $schemaVersion
        architectureVersion = $(if ($Manifest.architectureVersion) { [version]$Manifest.architectureVersion } else { $null })
        minimumScriptVersion = $(if ($Manifest.minimumScriptVersion) { [version]$Manifest.minimumScriptVersion } else { $null })
        scriptVersion = $script:ScriptVersion
        compatible = $true
    }
}

Export-ModuleMember -Function Get-XmipScriptVersion,Test-XmipManifestCompatibility
