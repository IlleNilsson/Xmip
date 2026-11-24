#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

<#
.SYNOPSIS
    What cargo or dotnet said failed, read from its lines: each crate or
    project, the test or the place, and the words that say why.

.DESCRIPTION
    The one reading of a tool's failure, for the landing and Core.Internal
    alike (open problem 146): Invoke-XmipTool keeps what the tool said and
    asks it here, and each part names what failed by it. Until 2026-11-24 a
    failed run said "Rust" or ".NET" and nothing more, and a run on a test
    computer left the lines that said why there.

    Style: doc/governance/powershell-style.md
#>


# The lines that say why a tool failed, where nothing more is known: the last
# of them are kept with the failure.
[string] $script:XmipToolTelling = '^(error|warning)|FAILED|panicked|\[-\]|could not compile'

# How many of those lines a failure keeps.
[int] $script:XmipToolTold = 20

# What cargo says as it runs a test program, the program's name in its file,
# without the hash cargo gives it: `Running unittests src/lib.rs
# (target/debug/deps/xmip_core-0a1b2c3d4e5f6a7b)`.
[string] $script:XmipCargoProgram = '^\s+Running (?:unittests )?\S+ \((?:.*[\\/])?' +
    '([^\\/]+?)(?:-[0-9a-f]{16})?(?:\.exe)?\)$'


function Get-XmipToolFailure {
    <#
        .SYNOPSIS
            Each failure -Line says, as Xmip.ToolFailure: Package, the crate
            or project cargo or MSBuild named, empty where none was; Test,
            the test or the target; Message, the words that say why; Path, the
            file a compiler or a formatter named, empty where none was.

        .PARAMETER Tool
            Whose lines: cargo or dotnet.

        .PARAMETER Line
            What it said, every line.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.ToolFailure')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('cargo', 'dotnet')]
        [string] $Tool,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Line
    )

    if ($Tool -eq 'cargo') {
        return Get-XmipCargoFailure -Line $Line
    }

    return Get-XmipDotnetFailure -Line $Line
}


function New-XmipToolFailure {
    <#
        .SYNOPSIS
            One failure as Get-XmipToolFailure returns it.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.ToolFailure')]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Package = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Test = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Message = '',

        [Parameter()]
        [AllowEmptyString()]
        [string] $Path = ''
    )

    return [pscustomobject]@{
        PSTypeName = 'Xmip.ToolFailure'
        Package    = $Package
        Test       = $Test
        Message    = $Message
        Path       = $Path
    }
}


function Get-XmipCargoFailure {
    <#
        .SYNOPSIS
            Get-XmipToolFailure for cargo: a crate that did not compile or
            lint, with the compiler's first error and its place; each test
            that failed, with what it panicked at; a test stopped after a
            minute; a file the formatter would change.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.ToolFailure')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Line
    )

    [List[string]] $failing = [List[string]]::new()
    [Dictionary[string, string]] $why = [Dictionary[string, string]]::new()
    [HashSet[string]] $named = [HashSet[string]]::new()
    [string] $program = ''
    [string] $reading = ''
    [string] $panicked = ''
    [string] $diagnostic = ''
    [string] $place = ''
    [string] $warning = ''
    [string] $warningPlace = ''
    [string] $placing = ''
    [bool] $summary = $false

    foreach ($one in $Line) {
        switch -Regex ($one) {
            $script:XmipCargoProgram {
                $program = $Matches[1]; $failing.Clear(); $reading = ''
                break
            }
            '^\s+Doc-tests (\S+)$' {
                $program = $Matches[1]; $failing.Clear(); $reading = ''
                break
            }
            '^test (.+?) \.\.\. FAILED$' {
                $failing.Add($Matches[1])
                break
            }
            '^test (\S+) has been running for over 60 seconds' {
                New-XmipToolFailure -Package $program -Test $Matches[1] -Message (
                    'ran a minute and was stopped, with the run')
                break
            }
            '^---- (.+?) stdout ----$' {
                $reading = $Matches[1]
                break
            }
            '^(failures:|test result: )' {
                $reading = ''
                break
            }
            "^thread '.*'(?: \(\d+\))? panicked at (.+?):?$" {
                if ($reading) {
                    $why[$reading] = "panicked at $($Matches[1])"
                    $panicked = $reading
                }

                break
            }
            '^error: test failed, to rerun pass `-p (\S+)(.*)`$' {
                [string] $package = $Matches[1]
                [string] $target = $Matches[2].Trim()
                [void] $named.Add($package)
                [string[]] $tests = @($target)

                if ($failing.Count -gt 0) {
                    $tests = $failing.ToArray()
                }


                foreach ($test in $tests) {
                    [string] $said = if ($why.ContainsKey($test)) { $why[$test] }
                    else { "its test program $target failed" }
                    New-XmipToolFailure -Package $package -Test $test -Message $said
                }

                $failing.Clear()
                break
            }
            '^error: \d+ targets? failed:$' {
                $summary = $true
                break
            }
            '^\s+`-p (\S+)(.*)`$' {
                if ($summary -and $named.Add($Matches[1])) {
                    New-XmipToolFailure -Package $Matches[1] -Test $Matches[2].Trim() -Message (
                        'its test program failed')
                }

                break
            }
            '^error: could not compile `([^`]+)`(.*)$' {
                [string] $said = "did not compile$($Matches[2])"

                if ($diagnostic) {
                    $said = $diagnostic
                }

                New-XmipToolFailure -Package $Matches[1] -Message $said -Path $place
                $diagnostic = ''; $place = ''
                break
            }
            # A warning fails every build under the estate's root (.cargo,
            # `build.warnings = "deny"`), and cargo then counts a crate's
            # warnings as an error: the crate, with the first of them.
            '^(error|warning): `([^`]+)` \(.+?\) generated \d+ warnings?' {
                if ($Matches[1] -eq 'error') {
                    New-XmipToolFailure -Package $Matches[2] -Path $warningPlace -Message (
                        "warns, and a warning fails the build: $warning")
                }

                $warning = ''; $warningPlace = ''
                break
            }
            '^error(\[\w+\])?: (.+)$' {
                if (-not $diagnostic) {
                    $diagnostic = $one.Trim(); $placing = 'error'
                }

                break
            }
            '^warning(\[\w+\])?: (.+)$' {
                if (-not $warning) {
                    $warning = $one.Trim(); $placing = 'warning'
                }

                break
            }
            '^\s*--> (.+?)(:\d+)*$' {
                [string] $at = $one.Trim().Substring(4)

                if ($placing -eq 'error') {
                    $place = $Matches[1]; $diagnostic += " at $at"
                }
                elseif ($placing -eq 'warning') {
                    $warningPlace = $Matches[1]; $warning += " at $at"
                }

                $placing = ''
                break
            }
            '^Diff in (.+?):(\d+):$' {
                New-XmipToolFailure -Message "not formatted as rustfmt formats it, from line $(
                    $Matches[2])" -Path $Matches[1]
                break
            }
            default {
                if ($panicked -and $one.Trim()) {
                    $why[$panicked] += ": $($one.Trim())"
                    $panicked = ''
                }
            }
        }
    }
}


function Get-XmipDotnetFailure {
    <#
        .SYNOPSIS
            Get-XmipToolFailure for dotnet: a project that did not build,
            with the compiler's error and its place; each test that failed,
            with its message. A project's tests are named by whoever ran
            them, which knows the project.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.ToolFailure')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Line
    )

    [HashSet[string]] $seen = [HashSet[string]]::new()
    [string] $test = ''
    [bool] $telling = $false

    foreach ($one in $Line) {
        switch -Regex ($one) {
            '^\s*(.+?)\((\d+),(\d+)\): error (\w+): (.+?)(?: \[(.+?)\])?$' {
                [string] $said = "error $($Matches[4]): $($Matches[5]) at $($Matches[1])(" +
                    "$($Matches[2]),$($Matches[3]))"
                # The project's name, its path split at either separator: what
                # MSBuild wrote on one system may be read on another.
                [string] $project = if ($Matches[6]) {
                    (($Matches[6] -split '::')[0] -split '[\\/]')[-1] -replace '\.csproj$', ''
                }

                if ($seen.Add($said)) {
                    New-XmipToolFailure -Package $project -Message $said -Path $Matches[1]
                }

                break
            }
            '^\s*[Ff]ailed (\S+?)(?: \[.*\]| \(.*\))?$' {
                $test = $Matches[1]; $telling = $false
                break
            }
            '^\s*Error Message:\s*$' {
                $telling = [bool] $test
                break
            }
            default {
                if ($test -and ($telling -or $one -match '^\s{2,}\S') -and $one.Trim()) {
                    if ($seen.Add("test $test")) {
                        New-XmipToolFailure -Test $test -Message $one.Trim()
                    }

                    $test = ''; $telling = $false
                }
            }
        }
    }

    # A test named and never told why.
    if ($test -and $seen.Add("test $test")) {
        New-XmipToolFailure -Test $test -Message 'failed'
    }
}
