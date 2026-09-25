#requires -PSEdition Core
#requires -Version 7.6.5

<#
    No node in the estate's code, tests, fixtures or help is named like a role.

    The owner, 2026-09-20: *Rn, Pn and Sn are arbitrary node names* (ADR-0056,
    amendment), and a node's role comes from its declared capability, never its
    name. The rig and its examples kept those names anyway, until the owner,
    2026-09-25: *Why does the test code include R1, P1 and S1, those are
    parameters to tests!* They were replaced the same day by names that carry
    no meaning — alpha, beta, gamma, delta, epsilon, zeta — and this file keeps
    them from creeping back: a name that reads as a stage invites the next
    reader to read the stage out of it, which is the defect ADR-0056 struck.

    What is looked for is a letter R, P or S followed by digits, standing
    where a node's name stands:

    - a scope or process name: node/<name>, node-<name>, handoff/<name>;
    - a handoff: <name>-><name>;
    - a declaration: <name>=receive, as --nodes, a roster and [run] say it;
    - a -NodeCapability entry: <name> = 'receive';
    - a parameter or flag that names nodes: -Nodes, -OnlineNodes, -Node,
      -Name, --name, --nodes, --online;
    - a quoted or backticked name on its own, as a list, a fixture key, an
      assertion or a help example carries it.

    Searched: module/, test/, template/, sdk/, Xmip/ and doc/ outside
    doc/decision/, in every language the estate writes and every text it
    keeps beside the code. The records under doc/decision/ are history and
    quote the owner as he spoke; they are not searched.

    Two kinds of token are not node names and are said here once:
    $script:Word, the products and specifications the estate integrates with,
    and $script:Value, the files whose token is a value inside a message.
#>

BeforeAll {
    $script:Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

    [string] $name = '[RPS][0-9]+'
    [string] $quote = '[''"`]'

    # Where a node's name stands, each place named for the failure message.
    $script:Place = [ordered]@{
        'a scope or process name'   = "(node|handoff)[/-]($name)\b"
        'a handoff'                 = "\b($name)->|->($name)\b"
        'a declaration'             = "\b($name)=(receive|process|send)\b"
        'a -NodeCapability entry'   = "\b($name)\s*=\s*$quote(receive|process|send)"
        'a parameter naming nodes'  =
            "(-Nodes|-OnlineNodes|-Node|-Name|--name|--nodes|--online)\s+$quote?($name)\b"
        'a quoted name'             = "$quote($name)$quote"
    }

    # Amazon S3, Siemens S7 and the FHIR releases: names of things Xmip talks
    # to, never of a node.
    $script:Word = @('S3', 'S7', 'R4', 'R5')

    # A token that is a value in a document a test reads or writes.
    $script:Value = @{
        'module/core/capability/path/dot/src/walk.rs'        = 'a SKU and a reference'
        'module/core/capability/path/dot/src/lib.rs'         = 'a reference header'
        'module/core/capability/path/json-pointer/src/lib.rs' = 'a reference field'
    }

    $script:Extension = @(
        '.rs', '.cs', '.ps1', '.psm1', '.psd1', '.razor', '.toml', '.md', '.json'
    )
    $script:Skip = @(
        'target', 'bin', 'obj', 'node_modules', '.ai-interaction', '.ai-work',
        '.local-work', '.git'
    )
    $script:Tree = @('module', 'test', 'template', 'sdk', 'Xmip', 'doc')
    $script:Self = 'test/NodeName.Test.ps1'

    <#
        .SYNOPSIS
        Every searched file beneath a directory, build output pruned.
    #>
    function Get-NodeNameFile([string] $At) {
        foreach ($file in [IO.Directory]::EnumerateFiles($At)) {
            if ([IO.Path]::GetExtension($file) -in $script:Extension) {
                $file
            }
        }

        foreach ($directory in [IO.Directory]::EnumerateDirectories($At)) {
            [string] $leaf = Split-Path -Leaf $directory
            [string] $relative = [IO.Path]::GetRelativePath($script:Root, $directory)

            if ($leaf -in $script:Skip -or ($relative -replace '\\', '/') -eq 'doc/decision') {
                continue
            }

            Get-NodeNameFile -At $directory
        }
    }

    <#
        .SYNOPSIS
        Every place a line names a node like a role, as file:line: place.
    #>
    function Find-NodeName([string] $Path, [string[]] $Line) {
        for ([int] $at = 0; $at -lt $Line.Count; $at++) {
            foreach ($place in $script:Place.Keys) {
                foreach ($match in [regex]::Matches($Line[$at], $script:Place[$place])) {
                    [string] $token = @($match.Groups | Select-Object -Skip 1 |
                            Where-Object { $_.Value -match '^[RPS][0-9]+$' })[0].Value

                    if ($token -notin $script:Word) {
                        "${Path}:$($at + 1): $place, $token"
                    }
                }
            }
        }
    }
}

Describe 'A node is never named like a role' {
    It 'finds no node named a stage letter and digits in code, tests, fixtures or help' {
        [string[]] $found = @(
            foreach ($tree in $script:Tree) {
                [string] $at = Join-Path $script:Root $tree

                if (-not (Test-Path -LiteralPath $at)) {
                    continue
                }

                foreach ($file in (Get-NodeNameFile -At $at)) {
                    [string] $path =
                        [IO.Path]::GetRelativePath($script:Root, $file) -replace '\\', '/'

                    if ($path -eq $script:Self -or $script:Value.ContainsKey($path)) {
                        continue
                    }

                    Find-NodeName -Path $path -Line @(Get-Content -LiteralPath $file)
                }
            }
        )

        $found | Should -BeNullOrEmpty -Because (
            'a node''s name carries no meaning; name it alpha, beta, gamma (ADR-0056)')
    }

    It 'recognizes each place a node''s name stands' {
        # Built, not written: this file is itself searched for nothing, and a
        # literal here would be the one it must not hold.
        [string] $role = 'R' + '1'
        [string[]] $sample = @(
            "scope = `"xmip:///C1/node/$role/receive`""
            "xmip-playground-C1-node-$role"
            "--nodes $role=receive,beta=send"
            "-NodeCapability @{ $role = 'receive' }"
            "Start-XmipTest -Nodes $role, beta"
            "nodes = [`"$role`"]"
            "id = `"alpha->$role`""
        )

        foreach ($line in $sample) {
            @(Find-NodeName -Path 'sample' -Line $line) | Should -Not -BeNullOrEmpty -Because $line
        }

        @(Find-NodeName -Path 'sample' -Line 'judge("S3", Response::new(204))') |
            Should -BeNullOrEmpty -Because 'Amazon S3 is a service, not a node'
        @(Find-NodeName -Path 'sample' -Line '[R:12 P:11 S:10]') |
            Should -BeNullOrEmpty -Because 'a stage letter and its rate are not a name'
    }

    It 'lists only value files that exist and still hold such a token' {
        [string[]] $stale = @(
            $script:Value.Keys | Where-Object {
                [string] $path = Join-Path $script:Root $_
                -not (Test-Path -LiteralPath $path) -or
                    (Get-Content -LiteralPath $path -Raw) -notmatch '[''"][RPS][0-9]+[''"]'
            }
        )

        $stale | Should -BeNullOrEmpty -Because 'the list says what is true'
    }
}
