#Requires -Version 7.6.5

# The deploy lists are the manifest, said twice. deploy/dsc/xmip-node.dsc.yaml
# and deploy/ansible/roles/xmip_node/defaults/main.yml each name every module
# a node carries, and the owner's rule (2026-09-08) is that every technology
# landed goes into both. On 2026-09-09 they were hand-edited three times in one
# day; a gate over the document is what the estate does instead of remembering.
#
# The rule: every technology architecture.toml declares scaffolded or beyond
# under a capability appears in both lists, once, and nothing appears that the
# manifest does not declare at that maturity. The language bindings of the
# contract capability (`primaryLanguage` set: c, cpp, go, java, python, rust,
# dotnet) are how a contract is written in that language, not a technology a
# Location names, and are not deployed; nor is a technology of an operator
# surface (gui's VS Code extension) — a surface has `primaryLanguage` itself
# and its children drive a node from outside (ADR-0014). What starts by
# default is a smaller set the deploy files own; the gate only asks that it
# is drawn from the list.

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module PSToml -ErrorAction Stop

    $manifest = ConvertFrom-Toml -InputObject (
        Get-Content -LiteralPath (Join-Path $script:Root 'architecture.toml') -Raw
    ) -ErrorAction Stop
    $deployed = [System.Collections.Generic.List[string]]::new()
    foreach ($capability in $manifest.xmip.core.Keys) {
        $node = $manifest.xmip.core[$capability]
        if ($node -isnot [System.Collections.IDictionary]) { continue }
        if ($node.Contains('primaryLanguage')) { continue }
        foreach ($leaf in $node.Keys) {
            $technology = $node[$leaf]
            if ($technology -isnot [System.Collections.IDictionary]) { continue }
            if (-not $technology.Contains('maturity')) { continue }
            if ($technology.maturity -in @('reserved', 'planned', 'retired')) { continue }
            if ($technology.Contains('primaryLanguage')) { continue }
            $deployed.Add("xmip-core-$capability-$leaf")
        }
    }
    $script:Declared = @($deployed | Sort-Object -Unique)

    $dsc = Get-Content -LiteralPath (
        Join-Path $script:Root 'deploy/dsc/xmip-node.dsc.yaml'
    ) -Raw
    function Read-DscList([string] $Text, [string] $Key) {
        if ($Text -notmatch "(?s)$Key = \[(?<body>.*?)\]") { return @() }
        return @([regex]::Matches($Matches.body, '"(xmip-core-[a-z0-9-]+)"') |
            ForEach-Object { $_.Groups[1].Value })
    }
    $script:DscPresent = @(Read-DscList $dsc 'present')
    $script:DscStarted = @(Read-DscList $dsc 'started')

    $ansible = Get-Content -LiteralPath (
        Join-Path $script:Root 'deploy/ansible/roles/xmip_node/defaults/main.yml'
    )
    $entries = @($ansible | ForEach-Object {
        if ($_ -match '^\s*-\s*\{\s*name:\s*(xmip-core-[a-z0-9-]+),\s*start:\s*(true|false)\s*\}') {
            [pscustomobject]@{ Name = $Matches[1]; Start = $Matches[2] -eq 'true' }
        }
    })
    $script:AnsiblePresent = @($entries | ForEach-Object Name)
    $script:AnsibleStarted = @($entries | Where-Object Start | ForEach-Object Name)
}

Describe 'The deploy lists carry what the manifest has built' {
    It 'declares something to deploy' {
        $script:Declared.Count | Should -BeGreaterThan 50
    }

    It 'DSC names every scaffolded technology, and nothing else' {
        $missing = @($script:Declared | Where-Object { $_ -notin $script:DscPresent })
        $extra = @($script:DscPresent | Where-Object { $_ -notin $script:Declared })
        ($missing + $extra) | Should -BeNullOrEmpty -Because (
            "missing from deploy/dsc: $($missing -join ', '); " +
            "not in the manifest: $($extra -join ', ')"
        )
    }

    It 'Ansible names every scaffolded technology, and nothing else' {
        $missing = @($script:Declared | Where-Object { $_ -notin $script:AnsiblePresent })
        $extra = @($script:AnsiblePresent | Where-Object { $_ -notin $script:Declared })
        ($missing + $extra) | Should -BeNullOrEmpty -Because (
            "missing from deploy/ansible: $($missing -join ', '); " +
            "not in the manifest: $($extra -join ', ')"
        )
    }

    It 'names each module once per list' {
        @($script:DscPresent | Group-Object | Where-Object Count -gt 1) | Should -BeNullOrEmpty
        @($script:AnsiblePresent | Group-Object | Where-Object Count -gt 1) |
            Should -BeNullOrEmpty
    }

    It 'starts only what it carries, and the same set in both' {
        @($script:DscStarted | Where-Object { $_ -notin $script:DscPresent }) |
            Should -BeNullOrEmpty
        @($script:DscStarted | Sort-Object) | Should -Be @($script:AnsibleStarted | Sort-Object)
    }
}
