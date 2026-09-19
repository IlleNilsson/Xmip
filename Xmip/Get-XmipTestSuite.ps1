#requires -Version 7.6.5

Set-StrictMode -Version Latest

# A test suite carries a provider, exactly as a module does (ADR-0011), and
# `core` is reserved for Xmip itself — so a name with no provider is already
# the reserved provider's, and Xmip's own two are spelled bare (ADR-0059,
# amendment 2026-09-19; the owner: "-Suite is Playground, Not Core.Playground").
# Said once here, so no surface spells the Playground's name for itself and
# none of them can disagree.
[string] $script:XmipPlaygroundSuite = 'Playground'
[string] $script:XmipEstateSuite = 'Estate'

# Where a provider declares a suite of its own: one TOML file per suite in
# this directory, relative to the repository root. Xmip's own source is not
# edited to make room for Acme.Playground — a file is dropped here.
[string] $script:XmipTestSuiteArea = 'test/suite'

function Get-XmipTestSuite {
    <#
        .SYNOPSIS
            Every test suite this estate knows, Xmip's own first: the name a
            caller gives -Suite, who provides it, and how it starts.

        .DESCRIPTION
            Playground and Estate are known to the module, so the
            estate's own gate runs on a fresh clone with nothing declared.
            Every other suite is a provider's, declared in a TOML file under
            test/suite and read here. A declaration that is malformed is
            REFUSED by name (ADR-0055) rather than skipped, because a suite
            that silently is not there is a test run nobody notices missing.

        .PARAMETER Path
            The directory of declarations. Defaults to test/suite under the
            repository. Nothing there, or no directory at all, means Xmip's
            own two suites and no others.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestSuite')]
    param(
        [Parameter()]
        [string] $Path
    )

    New-XmipTestSuite -Provider 'Core' -Name 'Playground' -Kind 'roll'
    New-XmipTestSuite -Provider 'Core' -Name 'Estate' -Kind 'pester'

    if ([string]::IsNullOrWhiteSpace($Path)) {
        [string] $root = Get-XmipRepositoryRoot
        $Path = Join-Path -Path $root -ChildPath $script:XmipTestSuiteArea
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    # A provider's bad declaration is loud and is that provider's alone. It
    # was written to throw here, which read every declaration before any suite
    # was chosen — so one third party's typo refused Estate and stopped
    # the estate's own gate. Nothing of another provider's may do that: the
    # broken one is warned about by name and is absent, so asking for it
    # refuses with the same words as a suite nobody declared, and Xmip's two
    # are unaffected (ADR-0055 clause 5; a warning is not silence).
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Filter '*.toml' -File)) {
        try {
            Read-XmipTestSuiteDeclaration -Path $file.FullName
        }
        catch {
            Write-Warning ([string]$_.Exception.Message)
        }
    }
}

function New-XmipTestSuite {
    <#
        .SYNOPSIS
            One suite as the Xmip.TestSuite object every surface reads. The
            canonical spelling is bare for Xmip's own — Playground, Estate —
            and Provider.Name for everyone else; a caller is matched against
            it without regard to case.

        .PARAMETER Provider
            Who publishes the suite. Core is Xmip itself (ADR-0011).

        .PARAMETER Name
            What the provider calls the suite: Playground, Estate.

        .PARAMETER Kind
            How it starts: roll is the Playground's detached roll, pester is
            the estate's Pester files, command is a provider's own command.

        .PARAMETER Command
            The command that starts a provider's suite.

        .PARAMETER Source
            The declaration this came from; empty for Xmip's own two.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestSuite')]
    param(
        [Parameter(Mandatory)]
        [string] $Provider,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('roll', 'pester', 'command')]
        [string] $Kind,

        [Parameter()]
        [string] $Command = '',

        [Parameter()]
        [string] $Source = ''
    )

    # `core` is the reserved provider (ADR-0011), so a bare name is already
    # Xmip's and printing Core. in front of it tells an operator nothing he
    # did not know. Xmip's own two are canonical bare; a provider's keeps the
    # slot that says who stands behind it (ADR-0059, amendment 2026-09-19).
    [string] $canonical = if ($Provider -ieq 'Core') { $Name } else { "$Provider.$Name" }

    return [PSCustomObject]@{
        PSTypeName = 'Xmip.TestSuite'
        Name       = $canonical
        Provider   = $Provider
        Suite      = $Name
        Kind       = $Kind
        Command    = $Command
        Source     = $Source
    }
}

function Read-XmipTestSuiteDeclaration {
    <#
        .SYNOPSIS
            One provider's suite, from the TOML file that declares it.

        .DESCRIPTION
            The file says who provides the suite, what it is called and the
            command that starts it. Three lines are the whole of it:

                provider = "Acme"
                name     = "Playground"
                command  = "Start-AcmeXmipTest"

            The command is the provider's, from the provider's own PowerShell
            module (ADR-0011 names it xmip-acme-powershell). Start-XmipTest
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
        provider = Get-XmipDeclaredText -Declaration $declared -Key 'provider'
        name     = Get-XmipDeclaredText -Declaration $declared -Key 'name'
        command  = Get-XmipDeclaredText -Declaration $declared -Key 'command'
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

function Get-XmipNamedTestSuite {
    <#
        .SYNOPSIS
            The suites a caller named, in the order Get-XmipTestSuite returns
            them, and nothing when the name or pattern matches none. The one
            place that decides what a name means, so a refusal and a run can
            never disagree about it.

        .DESCRIPTION
            A name is matched against the canonical spelling and against
            <Provider>.<Name>, so Playground and Core.Playground are the one
            suite: a bare name is the reserved provider's (ADR-0011), and the
            qualified form is literally what it means (ADR-0059, amendment
            2026-09-19). Case never matters, here or anywhere.

            The match is a wildcard, as -Test's is and as Get-XmipTestNode
            -Name's is (the owner, 2026-09-19: "Filter the -Suite as the -Test
            parameter"), so -Suite * is every suite this estate knows and
            -Suite *Play* is the Playground. A literal name holds no wildcard
            character and selects exactly one suite, so nothing an operator
            typed before this means anything else now.

        .PARAMETER Name
            The suite a caller asked for: a name, or a pattern naming a group.

        .PARAMETER Known
            The suites there are, from Get-XmipTestSuite.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestSuite')]
    param(
        [Parameter(Mandatory)]
        [SupportsWildcards()]
        [string] $Name,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Known = @()
    )

    return $Known | Where-Object {
        $_.Name -like $Name -or "$($_.Provider).$($_.Suite)" -like $Name
    }
}

function Get-XmipTestSuiteRefusal {
    <#
        .SYNOPSIS
            Why a suite name cannot be run, or the empty string when it can.
            Pure: it starts nothing and reads nothing but the suites it is
            given, so a refusal can be asserted without a run.

        .DESCRIPTION
            One voice for both, because -Suite is a filter now: a name that
            names no suite and a pattern that matches none are the same fault
            and are refused in the same words, naming what was given and the
            suites there are (ADR-0055 clause 2; ADR-0059, amendment
            2026-09-19). Said here and not at the parameter: a
            ValidatePattern refuses correctly and PowerShell wraps it, so the
            operator reads "Cannot validate argument on parameter 'Suite'"
            first and the estate's words second, which reads as the framework
            complaining rather than Xmip refusing (the owner, 2026-09-19).
            Nothing has started either way — this is the first thing the
            cmdlet does.

        .PARAMETER Name
            The suite a caller asked for: a name, or a pattern naming a group.

        .PARAMETER Known
            The suites there are, from Get-XmipTestSuite.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [SupportsWildcards()]
        [string] $Name,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]] $Known = @()
    )

    if (@(Get-XmipNamedTestSuite -Name $Name -Known $Known).Count -gt 0) {
        return ''
    }

    [string] $there = @($Known | ForEach-Object { $_.Name }) -join ', '

    [string] $area = $script:XmipTestSuiteArea

    # A pattern matches and a name is called: an operator who typed Nope*
    # is not told that no suite is called Nope*, which would read as a
    # spelling complaint about something he never spelled.
    [type] $wild = [System.Management.Automation.WildcardPattern]
    [string] $how = if ($wild::ContainsWildcardCharacters($Name)) { 'matches' } else { 'is called' }

    return ("REFUSED. No test suite $how $Name. The suites are $there. A " +
        "bare name is Xmip's own; a provider's suite is <Provider>.<Name>, " +
        "declared under $area — provider, name and the command that starts it.")
}

function Test-XmipWholeSuite {
    <#
        .SYNOPSIS
            Whether a run was asked for the whole suite rather than named
            tests. The one place that decides it, for every suite and every
            provider (the owner, 2026-09-19: -Suite with -Test excluded means
            run all tests in the test suite).

        .DESCRIPTION
            Playground and Estate both did this already and did it
            by two unrelated accidents — an unset XMIP_PLAYGROUND_SCENARIOS
            that the roll reads as every scenario, and an empty -Test that
            Pester reads as every file. Two behaviors that happen to agree are
            not a rule; this is the rule, and all three branches ask it.

        .PARAMETER Test
            The tests the caller named. Nothing named is the whole suite.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Test = @()
    )

    [string[]] $named = @(
        $Test | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne '*' }
    )

    return $named.Count -eq 0
}

function Expand-XmipTestName {
    <#
        .SYNOPSIS
            The tests a pattern names, from the tests a suite has.

        .DESCRIPTION
            Wildcards, never regular expressions (ADR-0059). The estate
            already chose them once — Get-XmipTestNode -Name is
            [SupportsWildcards()] and matches with -like — and they are
            PowerShell's own convention, so a parameter that takes them says
            so in its help. The two also disagree about a dot: Rust.Style is a
            real test of Estate, and a regular expression would match
            RustXStyle with it, while a wildcard reads the dot as the dot an
            operator typed.

            A pattern that matches nothing is REFUSED, naming the pattern and
            the tests there are (ADR-0055). A run that quietly selected no
            test would finish with nothing failing, which reads as success.

        .PARAMETER Test
            The patterns the caller gave. Order is kept and a test named
            twice is run once.

        .PARAMETER Known
            The tests the suite has.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [SupportsWildcards()]
        [string[]] $Test = @(),

        [Parameter(Mandatory)]
        [string[]] $Known
    )

    [System.Collections.Generic.List[string]] $chosen = @()

    foreach ($pattern in $Test) {
        [string[]] $found = @($Known | Where-Object { $_ -like $pattern })

        if ($found.Count -eq 0) {
            throw ("REFUSED. No test matches $pattern. The tests are " +
                "$($Known -join ', ').")
        }

        foreach ($name in $found) {
            if (-not $chosen.Contains($name)) {
                $chosen.Add($name)
            }
        }
    }

    return $chosen.ToArray()
}

function Get-XmipDeclaredText {
    <#
        .SYNOPSIS
            One string from a TOML declaration or a run record, and the empty
            string when the key is absent.

        .DESCRIPTION
            Set-StrictMode turns a missing key into an error at the point it
            is read, which would report a declaration's omission as a
            property that does not exist. A declaration that forgot a key is
            refused in words instead, and this is what lets it be.

        .PARAMETER Declaration
            What ConvertFrom-Toml returned, or nothing at all.

        .PARAMETER Key
            The key to read.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Declaration,

        [Parameter(Mandatory)]
        [string] $Key
    )

    if ($null -eq $Declaration) {
        return ''
    }

    [string[]] $keys = @($Declaration.Keys)

    if ($keys -notcontains $Key) {
        return ''
    }

    return "$($Declaration[$Key])"
}
