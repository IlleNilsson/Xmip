#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The module's one reader and writer of the estate's own TOML — its
    manifests (architecture.toml, allocation.toml, prerequisite.toml), its
    run and build records, its profiles, sites and environments — and the
    pair every document read is read with.

.DESCRIPTION
    About twenty-five copies of `Import-Module PSToml; Get-Content -Raw |
    ConvertFrom-Toml` and a regular expression reading one key stood where
    Read-XmipToml does now (2026-09-27). PSToml is loaded when a file is read
    or written, never at import, so a machine without it still imports the
    module and asks Install-XmipPrerequisite what it lacks.

    These are the tooling's files, and the tool that builds the runtime reads
    them, so it cannot need the runtime to read them (open problem 25, row
    u). The configuration Xmip runs — a cluster's cluster.xmip, a node's
    document — is read and written by the runtime's own reader through the
    operator module instead (Read-XmipConfiguration; ADR-0031, amendment
    2026-11-17).

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


function ConvertTo-XmipTomlTable {
    <#
        A TOML node, dictionary-shaped or object-shaped, as an ordered
        dictionary Write-XmipToml writes back: read key by key through
        Get-TomlKey and Get-TomlValue, a table inside it copied the same way,
        so a document can be changed and written whichever shape PSToml
        returned (2026-11-10). Nothing gives an empty one.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Node
    )

    [System.Collections.Specialized.OrderedDictionary] $table = [ordered]@{}

    foreach ($key in @(Get-TomlKey -Node $Node)) {
        $value = Get-TomlValue -Node $Node -Name $key
        [bool] $nested = $value -is [System.Collections.IDictionary] -or
            $value -is [System.Management.Automation.PSCustomObject]

        # Assigned in each branch: an if's output would unroll a list of one.
        if ($nested) {
            $table[$key] = ConvertTo-XmipTomlTable -Node $value
        }
        else {
            $table[$key] = $value
        }
    }

    return $table
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
        The module's one reader of the estate's own TOML: every tooling
        document comes through here and is then read with Get-TomlKey and
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
        The module's one TOML file writer, written whole
        (Write-XmipWholeFile). -NoClobber refuses a file that is already
        there, and the refusal is an error the caller can catch.
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
    Write-XmipWholeFile -Path $Path -Text $text -NoClobber:$NoClobber
}