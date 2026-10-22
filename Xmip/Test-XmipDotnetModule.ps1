#requires -PSEdition Core
#requires -Version 7.6.7

<#
.SYNOPSIS
    Verifying what is not a Cargo crate: .NET projects, Pester suites, the
    VS Code extension's shell and the Event bindings in other languages.

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
            Compiles a VS Code extension's TypeScript shell with TypeScript's
            native compiler. True when it compiled, or when the compiler is
            absent and said so.

        .DESCRIPTION
            ADR-0052 clause 6: the shell is verified by the gate the way its
            Rust is, and without Node.js (the owner, 2026-10-22; ADR-0014,
            amendment 2026-10-22): its packages restored from its lock, each
            checked against the lock's integrity, and its shell and webview
            compiled by the native compiler, an optional developer
            prerequisite (prerequisite.toml, [archive.typescript]). Every
            rule is the Rust server's and tested in Rust; the shell's lint
            and tests run in its CI alone, where Node lives in a throwaway
            runner, and are said SKIPPED here.

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

    [string] $root = Get-XmipRepositoryRoot
    $tsc = Get-XmipArchiveTool -Root $root -Name 'typescript'

    if (-not $tsc.Present) {
        [string] $note = "   SKIPPED: $Name/extension not compiled: TypeScript's native " +
            'compiler is absent. Install-XmipPrerequisite -Install -IncludeOptional'

        Write-Host $note -ForegroundColor Yellow

        return $true
    }

    Write-Host "   compiling $Name/extension with tsc $($tsc.Version)..." -ForegroundColor DarkGray

    try {
        Restore-XmipExtensionPackage -Extension $Path
        Invoke-XmipExtensionCompile -Root $root -Extension $Path
    }
    catch {
        Write-Host "   FAILED: $($_.Exception.Message)" -ForegroundColor Red

        return $false
    }

    [string] $skipped = "   SKIPPED: the shell's lint and tests run in its CI alone, where " +
        'Node.js lives in a throwaway runner (ADR-0014, amendment 2026-10-22)'

    Write-Host $skipped -ForegroundColor Yellow

    return $true
}

# The script a module verifies its Event bindings with, at its root
# (xmip-core-abi's, ADR-0065).
[string] $script:XmipEventBinding = 'verify-event-bindings.ps1'

# The most MSBuild nodes a landing's dotnet build or test runs at once, given
# as -m: to each.
[int] $script:XmipDotnetNodes = 4


function Test-XmipEventBinding {
    <#
        .SYNOPSIS
            Builds and tests a module's Event bindings in the languages
            besides Rust, through its own verify-event-bindings.ps1. True
            when every binding that ran passed.

        .DESCRIPTION
            Every language but Rust is optional for Xmip itself (the owner,
            2026-10-20: *every language except Rust is optional*): C and C++
            through zig, Java and Python are optional prerequisites
            (prerequisite.toml). A binding whose tool is absent here is
            SKIPPED in words by the script — "SKIPPED: Java not installed;
            the Java Event binding is not verified" — and fails nothing; one
            whose tool is here and fails fails the module. The script loads
            the runtime library XMIP_RUNTIME_LIBRARY names, which the landing
            builds first (Test-XmipRuntimeLibraryReader).

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

    Write-Host '   verifying the Event bindings...' -ForegroundColor DarkGray

    [string] $verify = Join-Path -Path $Path -ChildPath $script:XmipEventBinding
    [string[]] $arguments = @('-NoProfile', '-NonInteractive', '-File', $verify)

    if ($env:XMIP_RUNTIME_LIBRARY) {
        $arguments += @('-Library', $env:XMIP_RUNTIME_LIBRARY)
    }

    & pwsh @arguments 2>&1 | ForEach-Object { Write-Host "   $_" }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "   FAILED: an Event binding of $Name" -ForegroundColor Red

        return $false
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

    [System.IO.FileInfo[]] $project = @(Find-XmipFile -Path $Path -Filter '*.csproj')

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

    # Removed whatever the build said: one left per landing filled the
    # owner's C: with 142 of them, 5 GB, by 2026-10-14.
    try {
        foreach ($csproj in $project) {
            Write-Host "   building $($csproj.Name)..." -ForegroundColor DarkGray

            [string] $into = Join-Path -Path $output -ChildPath $csproj.BaseName

            [string[]] $building = @(
                'build', $csproj.FullName, '--output', $into, '--verbosity', 'quiet', '--nologo',
                "-m:$script:XmipDotnetNodes"
            )

            & dotnet @building 2>&1 |
                ForEach-Object { Write-Host $_ }

            if ($LASTEXITCODE -ne 0) {
                return $false
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $output -Recurse -Force -ErrorAction SilentlyContinue
    }

    # `.Test.csproj`, singular, like every test file in the estate.
    [System.IO.FileInfo[]] $suite = @(
        $project | Where-Object { $_.Name -match '\.Test\.csproj$' }
    )

    foreach ($csproj in $suite) {
        Write-Host "   dotnet test $($csproj.Name)..." -ForegroundColor DarkGray

        [string[]] $testing = @(
            'test', $csproj.FullName, '--verbosity', 'quiet', '--nologo',
            "-m:$script:XmipDotnetNodes"
        )

        & dotnet @testing 2>&1 |
            ForEach-Object { Write-Host $_ }

        if ($LASTEXITCODE -ne 0) {
            return $false
        }
    }

    return (Test-XmipPesterSuite -Path $Path -Name $Name -Built ($project.Count -gt 0))
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

    # In a fresh pwsh, at its top level: called from here, Pester would run
    # inside this module's scope, and a test that imports a module imports it
    # there rather than into the session it tests (2026-09-27: the prompt's
    # chaining test failed only under xgit for that reason).
    [string] $manifest = Join-Path -Path $PSScriptRoot -ChildPath 'Xmip.psd1'
    [string] $run = @'
param($Manifest, $Tests)
$xmip = Import-Module -Name $Manifest -PassThru
$configuration = & $xmip { param($Path) Get-XmipPesterConfiguration -Path $Path } $Tests
$result = Invoke-Pester -Configuration $configuration
[pscustomobject] @{
    Passed = $result.PassedCount
    Failed = $result.FailedCount
    Names  = @($result.Failed | ForEach-Object { $_.ExpandedPath })
} | ConvertTo-Json -Compress
'@
    [string] $file = "xmip-pester-$([guid]::NewGuid()).ps1"
    [string] $script = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $file
    Set-Content -LiteralPath $script -Value $run
    [string[]] $arguments = @(
        '-NoProfile', '-NonInteractive', '-File', $script, '-Manifest', $manifest, '-Tests', $tests
    )

    try {
        [string[]] $said = @(& pwsh @arguments 2>&1 | ForEach-Object { "$_" })
    }
    finally {
        Remove-Item -LiteralPath $script -ErrorAction SilentlyContinue
    }

    [string] $last = $said | Where-Object { $_ -like '{*' } | Select-Object -Last 1

    if (-not $last) {
        $said | ForEach-Object { Write-Host "   $_" -ForegroundColor Red }
        Write-Host '   FAILED. The Pester run gave no verdict.' -ForegroundColor Red

        return $false
    }

    $result = $last | ConvertFrom-Json

    [string] $tally = "   $($result.Passed) passed, $($result.Failed) failed"

    Write-Host $tally -ForegroundColor DarkGray

    foreach ($failure in $result.Names) {
        Write-Host "   FAILED $failure" -ForegroundColor Red
    }

    return ($result.Failed -eq 0)
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
