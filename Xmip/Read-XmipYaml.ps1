#requires -PSEdition Core
#requires -Version 7.6.7

<#
.SYNOPSIS
    The module's one YAML reader and writer.

.DESCRIPTION
    YAML is the configuration a tool that takes no TOML is given: Microsoft
    DSC's documents, manifests and parameters (CONTRIBUTING). Until
    2026-11-02 the DSC tests read YAML by running it through dsc's Echo
    resource and wrote JSON for dsc to read. powershell-yaml is loaded when
    a file is read or written, never at import, as PSToml is
    (Read-XmipToml.ps1).

    Style: doc/governance/powershell-style.md
#>


function Import-XmipYaml {
    <#
        Loads powershell-yaml, or says how to get it.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    try {
        Import-Module -Name powershell-yaml -ErrorAction Stop
    }
    catch {
        throw ('Reading or writing YAML needs powershell-yaml. ' +
            'Run Install-XmipPrerequisite -Role operator -Install.')
    }
}


function Read-XmipYaml {
    <#
        The module's one YAML file reader: a mapping comes back as a
        hashtable, a sequence as a list. Throws when the file does not parse.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    Import-XmipYaml
    [string] $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop

    return (ConvertFrom-Yaml -Yaml $text)
}


function Write-XmipYaml {
    <#
        The module's one YAML file writer.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Value
    )

    Import-XmipYaml
    [string] $text = ConvertTo-Yaml -Data $Value
    Set-Content -LiteralPath $Path -Value $text -Encoding utf8 -NoNewline -ErrorAction Stop
}
