#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The module's one TOML reader and writer, and the pair every document read
    through them is read with.

.DESCRIPTION
    About twenty-five copies of `Import-Module PSToml; Get-Content -Raw |
    ConvertFrom-Toml` and a regular expression reading one key stood where
    Read-XmipToml does now (2026-09-27). PSToml is loaded when a file is read
    or written, never at import, so a machine without it still imports the
    module and asks Install-XmipPrerequisite what it lacks.

    Style: doc/governance/powershell-style.md
#>


function Get-TomlKey {
    <#
        Lists the keys of a TOML node. ConvertFrom-Toml has returned a dictionary
        in one version of PSToml and a PSObject in the next, so nothing here asks
        which it is.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Node
    )

    if ($null -eq $Node) {
        return @()
    }

    if ($Node -is [System.Collections.IDictionary]) {
        return @($Node.Keys)
    }

    return @($Node.PSObject.Properties.Name)
}


function Get-TomlValue {
    <#
        Reads one key from a TOML node, dictionary-shaped or object-shaped,
        returning $Default when absent or null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Node,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $false)]
        $Default = $null
    )

    if ($null -eq $Node) {
        return $Default
    }

    if ($Node -is [System.Collections.IDictionary]) {
        if ($Node.Contains($Name) -and $null -ne $Node[$Name]) {
            return $Node[$Name]
        }

        return $Default
    }

    return (Get-XmipPropertyValue -Object $Node -Name $Name -Default $Default)
}


function Import-XmipToml {
    <#
        Loads PSToml, or says how to get it. The module imports without it
        (Install-XmipPrerequisite runs on a machine that lacks it), so the
        TOML reader and writer below load it when they are called.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    try {
        Import-Module -Name PSToml -ErrorAction Stop
    }
    catch {
        throw ('Reading or writing TOML needs PSToml. ' +
            'Run Install-XmipPrerequisite -Role developer -Install.')
    }
}


function Read-XmipToml {
    <#
        The module's one TOML file reader: every TOML document the estate
        reads comes through here and is then read with Get-TomlKey and
        Get-TomlValue, whichever shape PSToml returned. Throws when the file
        does not parse.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    Import-XmipToml
    [string] $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8 -ErrorAction Stop

    return (ConvertFrom-Toml -InputObject $text -ErrorAction Stop)
}


function Write-XmipToml {
    <#
        The module's one TOML file writer. -NoClobber refuses a file that is
        already there, and the refusal is an error the caller can catch.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Value,

        [Parameter(Mandatory = $false)]
        [switch] $NoClobber
    )

    Import-XmipToml
    [string] $text = ConvertTo-Toml -InputObject $Value -Depth 4

    [hashtable] $written = @{
        InputObject = $text
        LiteralPath = $Path
        Encoding    = 'utf8'
        NoClobber   = $NoClobber.IsPresent
        ErrorAction = 'Stop'
    }

    Out-File @written
}
