#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Reading and checking a provider's declared test suite.

.DESCRIPTION
    Apart from Get-XmipTestSuite.ps1 since 2026-09-22, when that file was 469 lines against the
    400 the estate allows a file and the owner asked for the estate to be
    consolidated. One subject per file.

    Style: doc/governance/powershell-style.md
#>


function Read-XmipTestSuiteDeclaration {
    <#
        .SYNOPSIS
            One provider's suite, from the TOML file that declares it.

        .DESCRIPTION
            The file says who provides the suite, what it is called and the
            command that starts it. Three lines are the whole of it, with
            Example standing in for whatever the third party calls itself —
            the estate names no placeholder company (ADR-0059, amendment
            2026-09-20):

                provider = "Example"
                name     = "Playground"
                command  = "Start-ExampleXmipTest"

            The command is the third party's, from its own PowerShell
            module (ADR-0011 names it xmip-<provider>-powershell). Start-XmipTest
            hands it everything -Suite was given beside it, and hands it no
            -Test when the operator named none, which means the whole suite.

        .PARAMETER Path
            The declaration file.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestSuite')]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    Import-Module PSToml -ErrorAction Stop
    $declared = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Toml

    [hashtable] $said = @{
        provider = [string](Get-TomlValue -Node $declared -Name 'provider' -Default '')
        name     = [string](Get-TomlValue -Node $declared -Name 'name' -Default '')
        command  = [string](Get-TomlValue -Node $declared -Name 'command' -Default '')
    }

    Assert-XmipTestSuiteDeclaration -Said $said -Path $Path

    [hashtable] $made = @{
        Provider = $said.provider
        Name     = $said.name
        Kind     = 'command'
        Command  = $said.command
        Source   = $Path
    }

    return New-XmipTestSuite @made
}


function Assert-XmipTestSuiteDeclaration {
    <#
        .SYNOPSIS
            A suite declaration says all three things and says them as names.
            Throws REFUSED naming the file otherwise; a half-written
            declaration is never read as no declaration.

        .PARAMETER Said
            The provider, name and command read from the file.

        .PARAMETER Path
            The file, so a refusal names which one.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Said,

        [Parameter(Mandatory)]
        [string] $Path
    )

    foreach ($key in 'provider', 'name', 'command') {
        if ([string]::IsNullOrWhiteSpace($Said[$key])) {
            throw ("REFUSED. $Path declares no $key. A suite declaration says " +
                'provider, name and command, and nothing less.')
        }
    }

    foreach ($word in 'provider', 'name') {
        if ($Said[$word] -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
            throw ("REFUSED. $Path declares $word '$($Said[$word])', which is not a " +
                'name: a letter, then letters and digits.')
        }
    }

    if ($Said.provider -ieq 'core') {
        throw ("REFUSED. $Path declares the provider core, which is reserved for Xmip " +
            'itself (ADR-0011). Name the provider who publishes the suite.')
    }
}
