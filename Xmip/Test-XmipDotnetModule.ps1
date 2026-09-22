#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Verifying what is not a Cargo crate: .NET projects, Pester suites and self-verifying modules.

.DESCRIPTION
    Apart from Publish-XmipChange.ps1 since 2026-09-22, when that file had grown
    to 1,586 lines against the 400 the estate allows a file, and the owner asked
    for the estate to be consolidated. The landing is one command made of several
    subjects; each subject is a file.

    Style: doc/governance/powershell-style.md
#>


function Test-XmipExtensionShell {
    <#
        .SYNOPSIS
            Compiles, lints and tests a VS Code extension's TypeScript shell.
            True when everything passed, or when npm is absent and said so.

        .DESCRIPTION
            ADR-0052 clause 6: the shell is verified by the gate the way its
            Rust is. Node is an optional developer prerequisite
            (prerequisite.toml), so a machine without it lands the shell
            unverified and is told, rather than being refused.

        .PARAMETER Path
            The extension directory, holding package.json.

        .PARAMETER Name
            The module path, for reporting.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        [string] $note = "   NOTE $Name/extension not verified: npm is absent. " +
            'Install-XmipPrerequisite -Role developer'

        Write-Host $note -ForegroundColor Yellow

        return $true
    }

    Push-Location -LiteralPath $Path

    try {
        foreach ($step in @('ci', 'run compile', 'run lint', 'test')) {
            Write-Host "   npm $step..." -ForegroundColor DarkGray

            & npm @($step -split ' ') 2>&1 | ForEach-Object { Write-Host $_ }

            if ($LASTEXITCODE -ne 0) {
                Write-Host "   FAILED npm $step" -ForegroundColor Red

                return $false
            }
        }
    }
    finally {
        Pop-Location
    }

    return $true
}


function Test-XmipDotnetModule {
    <#
        .SYNOPSIS
            Builds a .NET module and runs whatever tests it carries. True when
            everything passed.

        .DESCRIPTION
            ADR-0014 puts all four operator surfaces in .NET, and until
            2026-09-03 this file could verify none of them: it looked for a
            a `Cargo.toml`, found none, and said so. So `cli`, `powershell` and
            `gui` were skipped and landed only under `-All`, which means
            unverified — a third of the surface area outside the gate, on the
            day the PowerShell module gained eighteen tests nothing would run.

            Two kinds of test, because the estate has both. A Pester file under
            `test/` runs over a built module, which is what a PowerShell
            surface needs. A `*.Test.csproj` is `dotnet test`. A
            module with neither still builds, and building is the weakest
            verification that is still verification — reported as such rather
            than counted as passing tests.

        .PARAMETER Path
            The module's working tree.

        .PARAMETER Name
            The module path, for reporting.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Name
    )

    [System.IO.FileInfo[]] $project = @(
        Get-ChildItem -Path $Path -Filter '*.csproj' -Recurse -File |
            Where-Object { $_.FullName -notmatch '[\\/](obj|bin)[\\/]' }
    )

    # Built into a temporary directory, never into the project's own bin/.
    #
    # A loaded binary module locks its own assembly, and a PowerShell module is
    # loaded by whoever is using it. On 2026-09-03 this gate reported
    # xmip-core-powershell as failing when nothing was wrong with it: the
    # owner's terminal, open since the previous day, held
    # bin/Debug/net10.0/Xmip.PowerShell.dll and MSBuild gave up after ten
    # retries. A gate that an operator's open session can fail is not a gate,
    # and the first instinct — close the terminal — is the wrong fix.
    #
    # Verifying is not delivering. Nothing here needs bin/ to be current.
    [string] $stamp = [System.Guid]::NewGuid().ToString('n').Substring(0, 8)
    [string] $output = Join-Path ([System.IO.Path]::GetTempPath()) "xmip-verify-$stamp"

    foreach ($csproj in $project) {
        Write-Host "   building $($csproj.Name)..." -ForegroundColor DarkGray

        [string] $into = Join-Path -Path $output -ChildPath $csproj.BaseName

        & dotnet build $csproj.FullName --output $into --verbosity quiet --nologo 2>&1 |
            ForEach-Object { Write-Host $_ }

        if ($LASTEXITCODE -ne 0) {
            return $false
        }
    }

    # `.Test.csproj`, singular, like every test file in the estate. The plural
    # is tolerated until `Xmip.Abi.Tests` can be renamed: an editor's build
    # host held its directory on 2026-09-11.
    [System.IO.FileInfo[]] $suite = @(
        $project | Where-Object { $_.Name -match '\.Tests?\.csproj$' }
    )

    foreach ($csproj in $suite) {
        Write-Host "   dotnet test $($csproj.Name)..." -ForegroundColor DarkGray

        & dotnet test $csproj.FullName --verbosity quiet --nologo 2>&1 |
            ForEach-Object { Write-Host $_ }

        if ($LASTEXITCODE -ne 0) {
            return $false
        }
    }

    return (Test-XmipPesterSuite -Path $Path -Name $Name -Built ($project.Count -gt 0))
}


function Test-XmipSelfVerifyingModule {
    <#
        .SYNOPSIS
            Runs a module's own verify.ps1 and reports whether it passed.

        .DESCRIPTION
            ADR-0042 decision 3 admits a contract module in C, C++, Go, Java
            or Python over the C ABI. Teaching this tool one toolchain per
            language would put five build systems in one file; instead a
            repository in such a language carries a verify.ps1 at its root
            that builds and tests with whatever prerequisite.toml declares for
            it, and its exit code is the verdict. The script runs in the
            module's directory, in a fresh pwsh so it cannot lean on this
            module's state, and every line it writes is shown as it arrives.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Name
    )

    [string] $script = Join-Path -Path $Path -ChildPath 'verify.ps1'

    Write-Host "   verify.ps1..." -ForegroundColor DarkGray

    Push-Location -LiteralPath $Path

    try {
        & pwsh -NoProfile -NonInteractive -File $script 2>&1 | ForEach-Object { Write-Host $_ }

        if ($LASTEXITCODE -ne 0) {
            Write-Host "   FAILED. $Name verify.ps1 exited $LASTEXITCODE." -ForegroundColor Red

            return $false
        }
    }
    finally {
        Pop-Location
    }

    return $true
}


function Test-XmipPesterSuite {
    <#
        .SYNOPSIS
            Runs a module's Pester suite, if it has one. True when it passed or
            there was nothing to run.

        .DESCRIPTION
            Separate from its caller because Pester's result object needs
            handling that has nothing to do with building, and because a module
            with no suite at all is a report rather than a failure.

        .PARAMETER Path
            The module's working tree.

        .PARAMETER Name
            The module path, for reporting.

        .PARAMETER Built
            Whether anything was compiled. Only decides what is said when there
            is no suite: nothing built and nothing tested is worth flagging.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [bool] $Built
    )

    [string] $tests = Join-Path -Path $Path -ChildPath 'tests'

    [System.IO.FileInfo[]] $suite = @()

    if (Test-Path -LiteralPath $tests) {
        $suite = @(Get-ChildItem -Path $tests -Filter '*.Test.ps1' -Recurse -File)
    }

    if ($suite.Count -eq 0) {
        [string] $said = 'nothing to build or test'

        if ($Built) {
            $said = 'builds; no tests to run'
        }

        Write-Host "   $said" -ForegroundColor DarkGray

        return $Built
    }

    Write-Host "   running $($suite.Count) Pester file(s)..." -ForegroundColor DarkGray

    $result = Invoke-Pester -Configuration (Get-XmipPesterConfiguration -Path $tests)

    [string] $tally = "   $($result.PassedCount) passed, $($result.FailedCount) failed"

    Write-Host $tally -ForegroundColor DarkGray

    foreach ($failure in $result.Failed) {
        Write-Host "   FAILED $($failure.ExpandedPath)" -ForegroundColor Red
    }

    return ($result.FailedCount -eq 0)
}


<#
    .SYNOPSIS
    How Pester is told to find the estate's tests.

    .DESCRIPTION
    A test file is named for what it defines, in the singular, like every
    other file in the estate: `Allocation.Test.ps1` is the allocation test.
    Pester's own discovery pattern is the plural `*.Tests.ps1`, so the estate
    tells Pester its extension here rather than bending its files to the
    tool (the owner's ruling, 2026-09-11). Every run goes through this, so
    nothing discovers a different set.
#>
function Get-XmipPesterConfiguration {
    [CmdletBinding()]
    [OutputType('PesterConfiguration')]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $configuration = New-PesterConfiguration

    $configuration.Run.Path = $Path
    $configuration.Run.TestExtension = '.Test.ps1'
    $configuration.Run.PassThru = $true
    $configuration.Output.Verbosity = 'None'

    return $configuration
}
