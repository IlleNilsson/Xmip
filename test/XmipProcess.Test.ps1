#Requires -Version 7.6.5

# Every System Process Xmip owns is named xmip-<what> and declares its name,
# its location and its purpose (ADR-0053). Get-XmipProcess lists them with what
# they said; this holds the two rules the listing rests on: where the
# declarations are, and that a killed process's declaration does not outlive it.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # The cluster and node names are the test cluster's (ADR-0056, amendment
    # 2026-10-03).
    $script:Cluster = Get-XmipTestCluster
    $script:Named = @{ Name = $script:Cluster.Name; Node = $script:Cluster.Nodes[0] }
}

Describe 'Where a System Process declares itself' {
    It 'is the directory the node names, and this module keeps no rule for it' {
        # The rule is xmip-core-node's, tested there; the listing reads where
        # the node says (xmip_operate.h section 13). Until 2026-09-27 this
        # module kept the rule again, and read the files with a reader of its own.
        InModuleScope Xmip {
            Get-Command -Name 'Get-XmipProcessDirectory' -ErrorAction SilentlyContinue |
                Should -BeNullOrEmpty

            Import-XmipOperatorModule
            [string] $named = [Environment]::GetEnvironmentVariable('XMIP_PROCESS_DIRECTORY')
            [string] $expected = if ([string]::IsNullOrEmpty($named)) {
                Join-Path ([System.IO.Path]::GetTempPath()) 'xmip' 'process'
            }
            else {
                $named
            }

            # The same directory, however each side spells the temporary one.
            [string] $read = [Xmip.Surface.ProcessDeclaration]::Standing($null).Directory
            [string] $marker = "marker-$([System.Guid]::NewGuid().ToString('n'))"
            New-Item -ItemType Directory -Path $expected -Force | Out-Null
            New-Item -ItemType File -Path (Join-Path $expected $marker) | Out-Null

            try {
                Test-Path -LiteralPath (Join-Path $read $marker) | Should -BeTrue -Because $read
            }
            finally {
                Remove-Item -LiteralPath (Join-Path $expected $marker) -Force
            }
        }
    }
}

Describe 'What a killed process left behind' {
    It 'is dropped, because a process that is gone declares nothing' {
        [hashtable] $given = @{
            Area = $TestDrive; Location = "$($script:Cluster.Scope)/node/$($script:Named.Node)"
        }

        InModuleScope Xmip -Parameters $given {
            param($Area, $Location)

            # No process has this id: the highest a pid can be on Windows is
            # far below it, and Linux stops at four million by default.
            [string] $stale = Join-Path $Area 'xmip-playground-node-2000000000.toml'
            Set-Content -LiteralPath $stale -Encoding utf8 -Value @(
                'name = "xmip-playground-node"'
                "location = `"$Location`""
                'purpose = "test"'
                'pid = 2000000000'
            )

            $declared = Read-XmipProcessDeclaration -Path $Area

            $declared.Count | Should -Be 0
            Test-Path -LiteralPath $stale | Should -BeFalse
        }
    }

    It 'is not a declaration when the pid belongs to something that is not Xmip''s' {
        InModuleScope Xmip -Parameters @{ Area = $TestDrive } {
            param($Area)

            # This shell is alive and is not named xmip-*: a recycled pid must
            # not lend a dead declaration to a stranger.
            [string] $borrowed = Join-Path $Area "xmip-cli-$PID.toml"
            Set-Content -LiteralPath $borrowed -Encoding utf8 -Value @(
                'name = "xmip-cli"'
                'location = "xmip:///"'
                'purpose = "runtime"'
                "pid = $PID"
            )

            (Read-XmipProcessDeclaration -Path $Area).Count | Should -Be 0
            Test-Path -LiteralPath $borrowed | Should -BeFalse
        }
    }

    It 'answers nothing, and does not fail, where no process ever declared' {
        InModuleScope Xmip {
            [string] $nowhere = Join-Path ([System.IO.Path]::GetTempPath()) "xmip-none-$PID"
            (Read-XmipProcessDeclaration -Path $nowhere).Count | Should -Be 0
        }
    }
}

Describe 'What a Playground process is called' {
    <#
        ADR-0053, amendment 2026-09-20. The owner, reading eleven rows of
        Get-Process with two clusters up: "these process names does not tell an
        operator or developer much. Cluster, Node and test suite shall be
        incorporated in the process name."
    #>
    It 'carries its suite, its cluster and what it is' {
        InModuleScope Xmip -Parameters $script:Named {
            param($Name, $Node)

            Get-XmipPlaygroundImageName -Cluster $Name -What 'roll' |
                Should -Be "xmip-playground-$Name-roll"
            Get-XmipPlaygroundImageName -Cluster $Name -What 'cluster' |
                Should -Be "xmip-playground-$Name-cluster"
            Get-XmipPlaygroundImageName -Cluster $Name -What "node-$Node" |
                Should -Be "xmip-playground-$Name-node-$Node"

            # Clause 1 is untouched: the owner's one line still finds them.
            foreach ($what in 'roll', 'cluster', "node-$Node") {
                Get-XmipPlaygroundImageName -Cluster $Name -What $what |
                    Should -BeLike 'xmip-*'
            }
        }
    }

    It 'lets a node be called roll or cluster, and is still unambiguous' {
        # The owner, 2026-09-20: "A node is a node and can have one or more
        # roles, roll is something different." The marker carries the kind, so
        # no name has to be reserved for the shape's convenience.
        InModuleScope Xmip -Parameters $script:Named {
            param($Name, $Node)

            [string] $prefix = "xmip-playground-$Name"
            Get-XmipPlaygroundImageName -Cluster $Name -What 'node-roll' |
                Should -Be "$prefix-node-roll"
            Get-XmipPlaygroundImageName -Cluster $Name -What 'node-roll' |
                Should -Not -Be (Get-XmipPlaygroundImageName -Cluster $Name -What 'roll')

            Get-XmipPlaygroundImageKind -Name "$prefix-node-roll" | Should -Be 'Node'
            Get-XmipPlaygroundImageKind -Name "$prefix-node-cluster" | Should -Be 'Node'
            Get-XmipPlaygroundImageKind -Name "$prefix-roll" | Should -Be 'Roll'
            Get-XmipPlaygroundImageKind -Name "$prefix-cluster" | Should -Be 'Cluster'
        }
    }

    It 'says which of the three it is, named for a cluster or not' {
        InModuleScope Xmip -Parameters $script:Named {
            param($Name, $Node)

            # A node called node is a node too.
            [string] $prefix = "xmip-playground-$Name"
            [hashtable] $expected = @{
                "$prefix-roll"                    = 'Roll'
                "$prefix-cluster"                 = 'Cluster'
                "$prefix-node-$Node"              = 'Node'
                "$prefix-node-node"               = 'Node'
                'xmip-playground-roll'            = 'Roll'
                'xmip-playground-cluster'         = 'Cluster'
                'xmip-playground-node'            = 'Node'
                'xmip-gui-web'                    = ''
                'xmip-cli'                        = ''
                'notepad'                         = ''
            }

            foreach ($name in $expected.Keys) {
                Get-XmipPlaygroundImageKind -Name $name | Should -Be $expected[$name]
            }
        }
    }

    It 'is the Playground''s own where its image is, whatever the built file is called' {
        # The image is deliberately not the built binary: a process name is
        # its image's name. Nothing but this module writes that directory, so
        # a process running out of it is the Playground's without a warning
        # about a binary that changed under it.
        InModuleScope Xmip -Parameters $script:Named {
            param($Name, $Node)

            [string] $area = (Get-XmipPlaygroundLayout).Image
            [string] $image = Join-Path $area $Name "xmip-playground-$Name-node-$Node.exe"

            Test-XmipPlaygroundOwnImage -Path $image | Should -BeTrue
            Test-XmipPlaygroundOwnImage -Path '' | Should -BeFalse
            Test-XmipPlaygroundOwnImage -Path 'C:/Windows/notepad.exe' | Should -BeFalse
            Test-XmipPlaygroundOwnImage -Path (
                Join-Path (Get-XmipPlaygroundLayout).Playground 'target/debug/x.exe') |
                Should -BeFalse
        }
    }

    It 'lives under .local-work, device-local and never in the repository' {
        InModuleScope Xmip -Parameters $script:Named {
            param($Name, $Node)

            $layout = Get-XmipPlaygroundLayout

            $layout.Image | Should -BeLike '*.local-work*'
            Get-XmipPlaygroundImageArea -Cluster $Name |
                Should -Be (Join-Path $layout.Image $Name)
        }
    }
}
