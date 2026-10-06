#requires -PSEdition Core
#requires -Version 7.6.5

<#
    A test instead of a promise: what a document shows a reader to copy is
    held to what Xmip itself accepts.

    A documentation review of 2026-10-06 found a "minimal configuration" that
    was not TOML at all and an `xmip-cli subscriptions` pause the command
    line refuses for want of `--location`. Both had been read as true for
    weeks, because nothing read them but people.

    Two kinds of example are held here:

    - A ```toml block whose first line is `# a complete node file` or
      `# a complete cluster file` is a whole document, and the runtime that
      would start it judges it, through Test-XmipNodeConfiguration and
      xmip_validate_v1 — never a reading of this test's own. A block without
      the line is a fragment and is not read.
    - Every `xmip-cli` line a document shows names a command the command
      line's own usage (`Usage.Text` in module/core/operation/cli) lists and
      passes only the options it lists; a line in a fenced block, which a
      reader copies whole, also gives its command the arguments it requires
      and names what an act acts on. A span in prose is a mention.

    Decision records keep the words of their day and are not read.

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string[]] $script:Document = @(
        git -C $script:Root ls-files --recurse-submodules -- '*.md' |
            Where-Object { $_ -notmatch '^doc/decision/' } |
            Where-Object { Test-Path -LiteralPath (Join-Path $script:Root $_) }
    )

    [string] $usage = Join-Path $script:Root 'module/core/operation/cli/src/Xmip.Cli/Usage.cs'
    [string] $source = Get-Content -LiteralPath $usage -Raw
    [int] $opening = $source.IndexOf('"""')
    [int] $closing = $source.LastIndexOf('"""')
    [string] $script:Usage = $source.Substring($opening + 3, $closing - $opening - 3)
}

Describe 'A complete configuration a document shows is one the runtime would start' {
    BeforeAll {
        [System.Collections.Generic.List[PSCustomObject]] $marked =
            [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($document in $script:Document) {
            [string[]] $lines = @(Get-Content -LiteralPath (Join-Path $script:Root $document))
            [bool] $inside = $false
            [int] $start = 0
            [System.Collections.Generic.List[string]] $block =
                [System.Collections.Generic.List[string]]::new()

            for ([int] $at = 0; $at -lt $lines.Count; $at++) {
                [string] $line = $lines[$at]

                if (-not $inside -and $line -match '^\s*```toml\s*$') {
                    $inside = $true
                    $start = $at + 1
                    $block.Clear()
                    continue
                }

                if ($inside -and $line -match '^\s*```\s*$') {
                    $inside = $false
                    [string[]] $text = @($block | ForEach-Object { $_ })

                    if ($text.Count -gt 0 -and
                        $text[0].Trim() -match '^#\s*a complete (node|cluster) file\s*$') {
                        $marked.Add([PSCustomObject] @{
                            Where = "${document}:$start"
                            Text  = ($text -join "`n")
                        })
                    }

                    continue
                }

                if ($inside) {
                    $block.Add($line)
                }
            }
        }

        [PSCustomObject[]] $script:Marked = $marked.ToArray()

        # The runtime this estate built, in the one shared build directory
        # (Test-XmipChangeTree); landing builds it before anything is tested.
        [string] $target = if ($env:CARGO_TARGET_DIR) {
            $env:CARGO_TARGET_DIR
        }
        else {
            Join-Path -Path $script:Root -ChildPath '.ai-interaction/target-windows'
        }
        [string] $name = if ($IsWindows) {
            'xmip_core_runtime.dll'
        }
        elseif ($IsMacOS) {
            'libxmip_core_runtime.dylib'
        }
        else {
            'libxmip_core_runtime.so'
        }
        [string] $script:Runtime = Join-Path -Path $target -ChildPath "debug/$name"
    }

    It 'marks some, so the rule has something to hold' {
        $script:Marked.Count | Should -BeGreaterOrEqual 2 -Because (
            'node-configuration.md marks its minimal shape and its store as complete')
    }

    It 'is valid by the runtime''s own verdict' {
        $script:Runtime | Should -Exist -Because (
            'the runtime judges a configuration; build it: cargo build in module/platform/runtime')

        [hashtable] $given = @{
            Marked  = $script:Marked
            Runtime = $script:Runtime
            Area    = [string] $TestDrive
        }

        [string[]] $refused = @(
            InModuleScope Xmip -Parameters $given {
                param([PSCustomObject[]] $Marked, [string] $Runtime, [string] $Area)

                Import-XmipOperatorModule

                [int] $count = 0

                foreach ($example in $Marked) {
                    $count++
                    [string] $file = Join-Path -Path $Area -ChildPath "example-$count.toml"
                    Set-Content -LiteralPath $file -Value $example.Text -Encoding utf8NoBOM

                    [object] $verdict = Test-XmipNodeConfiguration -Path $file -Library $Runtime

                    if (-not $verdict.Ok) {
                        "$($example.Where): $($verdict.Problems -join '; ')"
                    }
                }
            }
        )

        $refused | Should -BeNullOrEmpty -Because (
            "a block marked complete is copied as it is:`n$($refused -join "`n")")
    }
}

Describe 'An xmip-cli line a document shows is one the command line takes' {
    BeforeAll {
        # The usage's command list: `xmip-cli <command> <required> [optional]`,
        # then two spaces and what it does, or the description on the next line.
        [hashtable] $script:Required = @{}

        # An example line passes options or a literal and is not one of them.
        [string] $listed = '(?m)^\s+xmip-cli ([a-z-]+)((?: [<\[][^>\]]+[>\]])*)(?:\s{2,}\S|\s*$)'

        foreach ($match in [regex]::Matches($script:Usage, $listed)) {
            [string] $command = $match.Groups[1].Value

            if (-not $script:Required.ContainsKey($command)) {
                $script:Required[$command] = [regex]::Matches(
                    $match.Groups[2].Value, '<[^>]+>').Count
            }
        }

        # Every option the usage names, and which of them take a value.
        [string[]] $script:Option = @(
            [regex]::Matches($script:Usage, '--[a-z][a-z-]*') |
                ForEach-Object { $_.Value } |
                Sort-Object -Unique
        )
        [string[]] $script:Valued = @(
            [regex]::Matches($script:Usage, '(--[a-z][a-z-]*) <') |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object -Unique
        )

        # What an act names, as the usage says it (its last paragraph): a node
        # by --location, and the one it acts on by --name, --id, --message or
        # journey's <id>.
        [hashtable] $script:Named = @{
            'subscriptions'       = '--name'
            'event-subscriptions' = '--id'
            'dead-messages'       = '--message'
            'journey'             = '<id>'
        }
        [string[]] $script:Act = @(
            '--pause', '--resume', '--remove', '--replay', '--retry', '--dismiss'
        )

        [System.Collections.Generic.List[PSCustomObject]] $shown =
            [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($document in $script:Document) {
            [string[]] $lines = @(Get-Content -LiteralPath (Join-Path $script:Root $document))
            [bool] $fenced = $false

            for ([int] $at = 0; $at -lt $lines.Count; $at++) {
                [string] $line = $lines[$at]

                if ($line -match '^\s*```') {
                    $fenced = -not $fenced
                    continue
                }

                [string[]] $said = @(
                    if ($fenced -and $line -match '^\s*(?:\$ )?(xmip-cli\b.*)$') {
                        $Matches[1]
                    }
                    elseif (-not $fenced) {
                        [regex]::Matches($line, '`(xmip-cli\b[^`]*)`') |
                            ForEach-Object { $_.Groups[1].Value }
                    }
                )

                foreach ($one in $said) {
                    # What follows two spaces or a comment is the line's prose.
                    [string] $command = ($one -split '\s{2,}|\s#')[0].Trim()
                    $shown.Add([PSCustomObject] @{
                        Where  = "${document}:$($at + 1)"
                        Line   = $command
                        Fenced = $fenced
                    })
                }
            }
        }

        [PSCustomObject[]] $script:Shown = $shown.ToArray()
    }

    It 'reads the usage it holds the documents to' {
        $script:Required.Count | Should -BeGreaterThan 10
        $script:Required['validate'] | Should -Be 1
        [string] $rule = 'An act names one, by --location at its node and --name, --id,'
        $script:Usage | Should -Match $rule
        [string] $because = 'the documents show the command line'
        $script:Shown.Count | Should -BeGreaterThan 10 -Because $because
    }

    It 'names a command the usage lists, its arguments and what an act acts on' {
        [string[]] $wrong = @(
            foreach ($example in $script:Shown) {
                # A placeholder is one argument however many words it holds.
                [string] $line = $example.Line -replace '<[^>]+>', '<x>'
                [string[]] $token = @($line -split '\s+' | Select-Object -Skip 1)
                [string] $command = ''
                [string[]] $argument = @()
                [string[]] $passed = @()

                for ([int] $at = 0; $at -lt $token.Count; $at++) {
                    [string] $word = $token[$at]

                    if ($word -match '^\[.*\]$') {
                        continue
                    }

                    if ($word.StartsWith('--')) {
                        # `--pause|--resume` shows a choice of two.
                        foreach ($option in ($word -split '\|')) {
                            $passed += $option
                        }

                        if ($word -in $script:Valued) {
                            $at++
                        }

                        continue
                    }

                    if ([string]::IsNullOrEmpty($command)) {
                        $command = $word
                    }
                    else {
                        $argument += $word
                    }
                }

                foreach ($option in $passed) {
                    if ($option -notin $script:Option) {
                        "$($example.Where): '$option' is no option of xmip-cli"
                    }
                }

                if ([string]::IsNullOrEmpty($command)) {
                    continue
                }

                if (-not $script:Required.ContainsKey($command)) {
                    "$($example.Where): '$command' is no command of xmip-cli"
                    continue
                }

                # In prose, `xmip-cli pause --who` names an option, and a
                # command named alone is a mention: only a fenced line is a
                # whole example.
                if (-not $example.Fenced) {
                    continue
                }

                if ($argument.Count -lt $script:Required[$command]) {
                    "$($example.Where): '$($example.Line)' gives $command " +
                    "$($argument.Count) of its $($script:Required[$command]) required arguments"
                }

                [bool] $acts = @($passed | Where-Object { $_ -in $script:Act }).Count -gt 0

                if ($acts -and $script:Named.ContainsKey($command)) {
                    [string] $names = $script:Named[$command]
                    [bool] $named = if ($names -eq '<id>') {
                        $argument.Count -gt 0
                    }
                    else {
                        $names -in $passed
                    }

                    if ('--location' -notin $passed -or -not $named) {
                        "$($example.Where): '$($example.Line)' acts without naming its " +
                        "node by --location and the one it acts on by $names"
                    }
                }
            }
        )

        $wrong | Should -BeNullOrEmpty -Because (
            "the command line refuses these as written:`n$($wrong -join "`n")")
    }
}
