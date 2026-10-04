#requires -PSEdition Core
#requires -Version 7.6.5

<#
    No cluster or node is named in the estate's code, tests or fixtures.

    The owner, 2026-09-20: *Rn, Pn and Sn are arbitrary node names* (ADR-0056,
    amendment), and a node's role comes from its declared capability, never its
    name. The owner, 2026-09-25: *Why does the test code include R1, P1 and S1,
    those are parameters to tests!* That was carried out as a rename to names
    that carry no meaning — alpha, beta, gamma, delta, epsilon, zeta — and the
    owner, 2026-10-03: *You invented alpha and beta some time ago*;
    *Parameters and configuration is the way to go, Xmip.toml* (ADR-0056,
    amendment 2026-10-03). A test takes its cluster's and nodes' names from the
    test cluster's xmip.toml through its language's one fixture — Rust's
    configure::fixture, .NET's TestCluster, PowerShell's Get-XmipTestCluster —
    and finds a node by what it declares or by its place. No name is written.

    A literal name is looked for where a name stands:

    - a scope: xmip:///<cluster>, and a node in one: .../node/<node>;
    - a process name: node-<name>, handoff/<name>;
    - a handoff: <name>-><name>;
    - a declaration: <name>=receiving, as --nodes and a roster say it;
    - a -NodeRole entry: <name> = 'receiving';
    - a configured name in text a test writes: cluster_name, node_name,
      [nodes.<name>];
    - a parameter or flag that names a cluster or nodes: -Cluster, -Nodes,
      -OnlineNodes, -Node, -Name, --cluster, --name, --nodes, --node,
      --online;
    - one of the names the owner types (Cn, Rn, Pn, Sn, CT), the Nn a test
      once numbered its nodes with, or the struck ones (alpha … zeta),
      quoted or backticked on its own, or standing before a / as a scope's
      part.

    Searched: .src/, module/, test/, template/, sdk/, Xmip/ and doc/ outside
    doc/decision/, in every language the estate writes and every text it
    keeps beside the code. The records under doc/decision/ are history and
    quote the owner as he spoke; they are not searched.

    Where a name may stand (ADR-0056, amendment 2026-10-03), and only there:

    - an xmip.toml, a cluster's configuration;
    - a README.md;
    - the .EXAMPLE and .PARAMETER sections of a comment-based help block in a
      .ps1 or .psm1 that is not a test;
    - a binary's usage text: a Rust `const USAGE`, and the `Text` of a C#
      Usage.cs, to the line that closes the string;
    - a snapshot fixture a test holds to a test cluster's xmip.toml, which
      is configuration that test checks: $script:Held names each and the
      test that holds it, and is held to that test in turn.

    Two kinds of token are not names and are said here once: $script:Word,
    the products and specifications the estate integrates with, and
    $script:Value, the files whose token is a value inside a message.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $quote = '[''"`]'
    # The names the owner types and the ones invented and struck: anywhere
    # quoted they are a name.
    [string] $known = '(?:[CRPSN][0-9]+|CT|alpha|beta|gamma|delta|epsilon|zeta)'
    # Any name, where only a name can stand.
    [string] $literal = '[A-Za-z][A-Za-z0-9_-]*'
    # The role words a node declares and the stage words it declared before
    # them (ADR-0056, amendment 2026-10-01): a name beside either stands where
    # a node's name stands.
    [string] $role = 'operational|monitoring|receiving|processing|sending|executing|' +
        'development|storage|receive|process|send'
    [string] $flag = '-Cluster|-Nodes|-OnlineNodes|-Node|--cluster|--nodes|--node|--online'

    # Where a name stands, each place named for the failure message. Every
    # name is captured as n; the first place to find a name on a line says it.
    # A scope whose host is omitted addresses a kind across the estate, as
    # xmip:///transport/ftp does (observability-model.md): a kind, not a name.
    [string] $kind = 'transport'
    $script:Place = [ordered]@{
        # A name a test makes unique, a prefix and a value it formats in,
        # is not written: the prefix alone is no name.
        'a scope'                  =
            "(?i:xmip):///(?!(?:$kind)/)(?>(?<n>$literal))(?![{`$])"
        'a node in a scope'        =
            "(?:[})]|xmip:///[^/\s]*|\$\w+)/node/(?<n>$literal)|(?<!\w)${quote}node/(?<n>$literal)"
        'a process name'           = "(?<!\w)(?:node|handoff)[/-](?<n>$known)\b"
        'a handoff'                =
            "\b(?<n>$known)->|->(?<n>$known)\b|$quote(?<n>$literal)->(?<n>$literal)$quote"
        # A query's parameter, ?phase=receive, is no declaration.
        'a declaration'            = "(?<![\w`$\{?&])(?<n>$literal)=(?:$role)\b"
        'a -NodeRole entry'        = "(?<![\w`$])(?<n>$known)\s*=\s*$quote(?:$role)"
        'a configured name'        =
            "\b(?:cluster_name|node_name)\s*[=:]\s*\\?$quote(?<n>$literal)|" +
            "\[nodes\.(?<n>$literal)\]"
        'a parameter naming nodes' =
            "(?:$flag|-Name|--name)\s+$quote?(?<n>$known)\b|" +
            "(?:$flag)\s+$quote(?<n>$literal)$quote|" +
            "$quote--(?:cluster|nodes?|online)$quote\s*,\s*$quote(?<n>$literal)$quote"
        'a quoted name'            = "(?<!\w)$quote(?<n>$known)$quote"
        'a scope''s part'          = "(?<![\w-])(?<n>$known)/(?=\w)"
    }

    # Amazon S3, Siemens S7 and the FHIR releases: names of things Xmip talks
    # to, never of a node; and .NET's N0, a number format.
    $script:Word = @('S3', 'S7', 'R4', 'R5', 'N0')

    # A token that is a value in a document a test reads or writes.
    $script:Value = @{
        'module/core/capability/path/dot/src/walk.rs'             = 'a SKU and a reference'
        'module/core/capability/path/dot/src/lib.rs'              = 'a reference header'
        'module/core/capability/path/json-pointer/src/lib.rs'     = 'a reference field'
        'module/core/capability/transport/aws-kinesis/src/lib.rs' = 'a record''s payload'
        'module/core/capability/transport/mqtt/src/client_id.rs'  = 'a topic'
        'module/core/capability/contract/toml/src/lib.rs'         = 'a layout''s type word'
    }

    # A snapshot fixture whose names a test holds to a test cluster's
    # xmip.toml: the test's file and the test.
    [string] $surface = 'module/foundation/abi/dotnet/Xmip.Surface.Test'
    $script:Held = @{
        "$surface/Fixture/cluster.toml"    = @{
            Test = "$surface/ClusterSnapshotTest.cs"
            Name = 'TheClusterFixtureIsTheTestClustersOwn'
        }
        "$surface/Fixture/snapshot.toml"   = @{
            Test = "$surface/ClusterSnapshotTest.cs"
            Name = 'TheNodesAreWhatThePublisherDrawsAsNodes'
        }
        "$surface/Fixture/cluster-c2.toml" = @{
            Test = "$surface/ClusterSurfacesTest.cs"
            Name = 'TheSecondFixtureIsTheSecondTestClustersOwn'
        }
    }

    $script:Extension = @(
        '.rs', '.cs', '.ps1', '.psm1', '.psd1', '.razor', '.toml', '.md', '.json'
    )
    $script:Candidate = [regex]::new(
        '(?i:xmip):///|alpha|beta|gamma|delta|epsilon|zeta|\b(?:[CRPSN][0-9]+|CT)\b|' +
        "=(?:$role)\b|cluster_name|node_name|\[nodes\.", 'Compiled')
    $script:Skip = @(
        'target', 'bin', 'obj', 'node_modules', '.ai-interaction', '.ai-work',
        '.local-work', '.git'
    )
    $script:Tree = @('.src', 'module', 'test', 'template', 'sdk', 'Xmip', 'doc')
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
        The indexes of the lines of a file where the owner's names belong:
        all of an xmip.toml and a README.md, the .EXAMPLE and .PARAMETER
        sections of a script's help, a binary's usage text.
    #>
    function Get-NodeNameHelpLine([string] $Path, [string[]] $Line) {
        [string] $leaf = ($Path -split '/')[-1]
        [string] $extension = [IO.Path]::GetExtension($leaf)
        [bool] $test = $Path -like 'test/*' -or $leaf -like '*.Test.ps1'

        if ($leaf -eq 'README.md' -or $leaf -like '*xmip.toml') {
            return 0..([Math]::Max($Line.Count - 1, 0))
        }

        if ($extension -in '.ps1', '.psm1' -and -not $test) {
            [bool] $inHelp = $false
            [string] $section = ''

            for ([int] $at = 0; $at -lt $Line.Count; $at++) {
                if (-not $inHelp -and $Line[$at] -match '^\s*<#') {
                    $inHelp = $true
                    $section = ''
                }

                if ($inHelp) {
                    if ($Line[$at] -match '^\s*\.([A-Za-z]+)\b') {
                        $section = $Matches[1].ToUpperInvariant()
                    }

                    if ($section -in 'EXAMPLE', 'PARAMETER') {
                        $at
                    }

                    if ($Line[$at] -match '#>') {
                        $inHelp = $false
                    }
                }
            }

            return
        }

        [string] $opens = switch ($extension) {
            '.rs' { '^\s*(pub\s+)?const\s+USAGE\s*:' }
            '.cs' { if ($leaf -eq 'Usage.cs') { '^\s*public\s+const\s+string\s+Text\s*=' } }
        }

        if (-not $opens) {
            return
        }

        [bool] $inUsage = $false

        for ([int] $at = 0; $at -lt $Line.Count; $at++) {
            if (-not $inUsage -and $Line[$at] -match $opens) {
                $inUsage = $true
            }

            if ($inUsage) {
                $at

                if ($Line[$at] -match '";\s*$') {
                    $inUsage = $false
                }
            }
        }
    }

    <#
        .SYNOPSIS
        Every name a line writes, once, as file:line: place, name. Where the
        owner's names belong is passed over (Get-NodeNameHelpLine).
    #>
    function Find-NodeName([string] $Path, [string[]] $Line) {
        $help = [Collections.Generic.HashSet[int]]::new()

        foreach ($at in @(Get-NodeNameHelpLine -Path $Path -Line $Line)) {
            [void] $help.Add([int] $at)
        }

        for ([int] $at = 0; $at -lt $Line.Count; $at++) {
            if ($help.Contains($at)) {
                continue
            }

            $said = [Collections.Generic.HashSet[string]]::new()

            foreach ($place in $script:Place.Keys) {
                foreach ($match in [regex]::Matches($Line[$at], $script:Place[$place])) {
                    foreach ($capture in $match.Groups['n'].Captures) {
                        [string] $token = $capture.Value

                        if ($token -notin $script:Word -and $said.Add($token)) {
                            "${Path}:$($at + 1): $place, $token"
                        }
                    }
                }
            }
        }
    }
}

Describe 'No cluster or node is named in code or tests' {
    It 'finds no literal cluster or node name in code, tests, fixtures or documents' {
        [string[]] $found = @(
            foreach ($tree in $script:Tree) {
                [string] $at = Join-Path $script:Root $tree

                if (-not (Test-Path -LiteralPath $at)) {
                    continue
                }

                foreach ($file in (Get-NodeNameFile -At $at)) {
                    [string] $path =
                        [IO.Path]::GetRelativePath($script:Root, $file) -replace '\\', '/'

                    if ($path -eq $script:Self -or $script:Value.ContainsKey($path) -or
                        $script:Held.ContainsKey($path)) {
                        continue
                    }

                    # One pass over the file's text decides whether its lines
                    # need reading at all: most hold no name, and a
                    # line-by-line match over the estate took over an hour.
                    [string] $text = [IO.File]::ReadAllText($file)

                    if (-not $script:Candidate.IsMatch($text)) {
                        continue
                    }

                    Find-NodeName -Path $path -Line ($text -split '\r?\n')
                }
            }
        )

        $found | Should -BeNullOrEmpty -Because (
            ('a name is configuration: take it from the test cluster''s xmip.toml ' +
                'through the fixture, by role or place (ADR-0056, amendment 2026-10-03)'))
    }

    It 'recognizes each place a name stands' {
        # Taken, not written: this file's names come from the test cluster
        # as every test's do.
        $cluster = Get-XmipTestCluster
        [string] $node = $cluster.Nodes[0]
        [string] $other = $cluster.Nodes[1]
        [string] $struck = 'al' + 'pha'
        [string] $any = 'la' + 'b'
        [string[]] $sample = @(
            "scope = `"$($cluster.Scope)/node/$node/receive`""
            "scope = `"xmip:///$any`""
            "format!(`"{}/node/$any/receive`", cluster.scope())"
            "`"node/$any/process`""
            "xmip-playground-$($cluster.Name)-node-$node"
            "--nodes $any=receiving,$other=sending"
            "-NodeRole @{ $node = 'receiving' }"
            "Start-XmipTest -Nodes $node, $other"
            "Start-XmipTest -Cluster '$any'"
            "[`"--cluster`", `"$any`"]"
            "nodes = [`"$node`"]"
            "id = `"$any->$other`""
            "cluster_name = \`"$any\`""
            "[nodes.$any]"
            "holder: `"$struck`".into()"
            "`"$struck/receive/tcp`""
            "TestNode::join(`"$('N' + '2')`", &authority, &roster)"
        )

        foreach ($line in $sample) {
            @(Find-NodeName -Path 'sample' -Line $line) | Should -Not -BeNullOrEmpty -Because $line
        }

        @(Find-NodeName -Path 'sample' -Line 'judge("S3", Response::new(204))') |
            Should -BeNullOrEmpty -Because 'Amazon S3 is a service, not a node'
        @(Find-NodeName -Path 'sample' -Line '[R:12 P:11 S:10]') |
            Should -BeNullOrEmpty -Because 'a stage letter and its rate are not a name'
        @(Find-NodeName -Path 'sample' -Line 'format!("{}/node/{}", scope, node.name)') |
            Should -BeNullOrEmpty -Because 'a name taken from the test cluster is not written'
        @(Find-NodeName -Path 'sample' -Line 'scope = $"xmip:///follow-{Guid.NewGuid():n}";') |
            Should -BeNullOrEmpty -Because 'a name a test makes unique is not written'
        @(Find-NodeName -Path 'sample' -Line '`xmip:///transport/ftp?phase=receive` addresses') |
            Should -BeNullOrEmpty -Because 'a scope with its host omitted names a kind'
        @(Find-NodeName -Path 'sample' -Line 'let delta = before - after; // pre-alpha') |
            Should -BeNullOrEmpty -Because 'a word in a protocol is not a name'
        @(Find-NodeName -Path 'sample' -Line "near.send(`"`", b`"$node`")") |
            Should -BeNullOrEmpty -Because 'a payload''s bytes are not a name'
    }

    It 'allows the owner''s names in help and configuration and refuses them in code' {
        $cluster = Get-XmipTestCluster
        [string] $example = "Start-XmipTest -Nodes $($cluster.Nodes[0])"
        [string[]] $script = @(
            'function Start-Sample {'
            '    <#'
            '        .DESCRIPTION'
            "            $example"
            '        .PARAMETER Nodes'
            "            $example"
            '        .EXAMPLE'
            "            $example"
            '    #>'
            "    $example"
            '}'
        )

        [string[]] $found = @(Find-NodeName -Path 'Xmip/Start-Sample.ps1' -Line $script)
        $found | Should -HaveCount 2 -Because 'the description and the body are not help examples'
        $found[0] | Should -BeLike 'Xmip/Start-Sample.ps1:4:*'
        $found[1] | Should -BeLike 'Xmip/Start-Sample.ps1:10:*'

        @(Find-NodeName -Path 'test/Start-Sample.Test.ps1' -Line $script) |
            Should -HaveCount 4 -Because 'a test''s names are configuration, never examples'
        @(Find-NodeName -Path 'module/core/example/README.md' -Line $example) |
            Should -BeNullOrEmpty -Because 'a README shows the owner''s names'
        @(Find-NodeName -Path 'test/xmip.toml' -Line "[nodes.$($cluster.Nodes[0])]") |
            Should -BeNullOrEmpty -Because 'an xmip.toml is where a name is configured'
        @(Find-NodeName -Path 'doc/guide.md' -Line $example) |
            Should -Not -BeNullOrEmpty -Because 'only a README.md is help'

        [string] $node = $cluster.Nodes[0]
        [string[]] $rust = @(
            'const USAGE: &str = "usage: cluster --nodes <a,b> \'
            "     example: cluster --nodes $node=receiving`";"
            "let given = [`"--nodes`", `"$node=receiving`"];"
        )
        [string[]] $inRust = @(Find-NodeName -Path 'test/core/sample/src/main.rs' -Line $rust)
        $inRust | Should -HaveCount 1 -Because 'a usage text is help and the line after it is code'
        $inRust[0] | Should -BeLike '*main.rs:3:*'
    }

    It 'lists only value files that exist and still hold such a token' {
        [string[]] $stale = @(
            $script:Value.Keys | Where-Object {
                [string] $path = Join-Path $script:Root $_
                -not (Test-Path -LiteralPath $path) -or
                    -not (Find-NodeName -Path $_ -Line (Get-Content -LiteralPath $path))
            }
        )

        $stale | Should -BeNullOrEmpty -Because 'the list says what is true'
    }

    It 'passes over only a fixture a test holds to a test cluster' {
        foreach ($fixture in $script:Held.Keys) {
            $held = $script:Held[$fixture]
            [string] $leaf = Split-Path -Leaf $fixture
            [string] $test = Join-Path $script:Root $held.Test

            Test-Path -LiteralPath (Join-Path $script:Root $fixture) |
                Should -BeTrue -Because "$fixture is listed"
            Test-Path -LiteralPath $test | Should -BeTrue -Because "$($held.Test) holds it"
            [string] $text = [IO.File]::ReadAllText($test)
            $text | Should -Match "\b$($held.Name)\(" -Because "$($held.Test) holds $leaf"
            $text | Should -Match ([regex]::Escape("`"$leaf`"")) -Because (
                "$($held.Test) reads $leaf")
            $text | Should -Match 'TestCluster\.Read(Other)?\(\)' -Because (
                'it holds the fixture to a test cluster')
        }
    }
}
