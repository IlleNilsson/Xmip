#Requires -Version 7.6.5

# Every System Process Xmip owns is named xmip-<what> and declares its name,
# its location and its purpose (ADR-0053). Get-XmipProcess lists them with what
# they said; this holds the two rules the listing rests on: where the
# declarations are, and that a killed process's declaration does not outlive it.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'Xmip' 'Xmip.psd1') -Force
}

Describe 'Where a System Process declares itself' {
    It 'is the directory the node names' {
        InModuleScope Xmip {
            [string] $before = $env:XMIP_PROCESS_DIRECTORY

            try {
                $env:XMIP_PROCESS_DIRECTORY = 'D:\somewhere\process'
                Get-XmipProcessDirectory | Should -Be 'D:\somewhere\process'
            }
            finally {
                $env:XMIP_PROCESS_DIRECTORY = $before
            }
        }
    }

    It 'is xmip/process under the temporary directory when the node names none' {
        InModuleScope Xmip {
            [string] $before = $env:XMIP_PROCESS_DIRECTORY

            try {
                $env:XMIP_PROCESS_DIRECTORY = ''
                [string] $expected = Join-Path ([System.IO.Path]::GetTempPath()) 'xmip' 'process'
                Get-XmipProcessDirectory | Should -Be $expected
            }
            finally {
                $env:XMIP_PROCESS_DIRECTORY = $before
            }
        }
    }
}

Describe 'What a killed process left behind' {
    It 'is dropped, because a process that is gone declares nothing' {
        InModuleScope Xmip -Parameters @{ Area = $TestDrive } {
            param($Area)

            # No process has this id: the highest a pid can be on Windows is
            # far below it, and Linux stops at four million by default.
            [string] $stale = Join-Path $Area 'xmip-playground-node-2000000000.toml'
            Set-Content -LiteralPath $stale -Encoding utf8 -Value @(
                'name = "xmip-playground-node"'
                'location = "xmip:///C1/node/R1"'
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
        InModuleScope Xmip {
            Get-XmipPlaygroundImageName -Cluster 'W1' -What 'roll' |
                Should -Be 'xmip-playground-W1-roll'
            Get-XmipPlaygroundImageName -Cluster 'W1' -What 'cluster' |
                Should -Be 'xmip-playground-W1-cluster'
            Get-XmipPlaygroundImageName -Cluster 'W1' -What 'node-R1' |
                Should -Be 'xmip-playground-W1-node-R1'

            # Clause 1 is untouched: the owner's one line still finds them.
            foreach ($what in 'roll', 'cluster', 'node-R1') {
                Get-XmipPlaygroundImageName -Cluster 'W1' -What $what |
                    Should -BeLike 'xmip-*'
            }
        }
    }

    It 'lets a node be called roll or cluster, and is still unambiguous' {
        # The owner, 2026-09-20: "A node is a node and can have one or more
        # roles, roll is something different." The marker carries the kind, so
        # no name has to be reserved for the shape's convenience.
        InModuleScope Xmip {
            Get-XmipPlaygroundImageName -Cluster 'U1' -What 'node-roll' |
                Should -Be 'xmip-playground-U1-node-roll'
            Get-XmipPlaygroundImageName -Cluster 'U1' -What 'node-roll' |
                Should -Not -Be (Get-XmipPlaygroundImageName -Cluster 'U1' -What 'roll')

            Get-XmipPlaygroundImageKind -Name 'xmip-playground-U1-node-roll' |
                Should -Be 'Node'
            Get-XmipPlaygroundImageKind -Name 'xmip-playground-U1-node-cluster' |
                Should -Be 'Node'
            Get-XmipPlaygroundImageKind -Name 'xmip-playground-U1-roll' |
                Should -Be 'Roll'
            Get-XmipPlaygroundImageKind -Name 'xmip-playground-U1-cluster' |
                Should -Be 'Cluster'
        }
    }

    It 'says which of the three it is, named for a cluster or not' {
        InModuleScope Xmip {
            [hashtable] $expected = @{
                'xmip-playground-W1-roll'         = 'Roll'
                'xmip-playground-W1-cluster'      = 'Cluster'
                'xmip-playground-W1-node-R1'      = 'Node'
                'xmip-playground-W1-node-node-01' = 'Node'
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
        InModuleScope Xmip {
            [string] $area = (Get-XmipPlaygroundLayout).Image
            [string] $image = Join-Path $area 'W1' 'xmip-playground-W1-node-R1.exe'

            Test-XmipPlaygroundOwnImage -Path $image | Should -BeTrue
            Test-XmipPlaygroundOwnImage -Path '' | Should -BeFalse
            Test-XmipPlaygroundOwnImage -Path 'C:/Windows/notepad.exe' | Should -BeFalse
            Test-XmipPlaygroundOwnImage -Path (
                Join-Path (Get-XmipPlaygroundLayout).Playground 'target/debug/x.exe') |
                Should -BeFalse
        }
    }

    It 'lives under .local-work, device-local and never in the repository' {
        InModuleScope Xmip {
            $layout = Get-XmipPlaygroundLayout

            $layout.Image | Should -BeLike '*.local-work*'
            Get-XmipPlaygroundImageArea -Cluster 'W1' |
                Should -Be (Join-Path $layout.Image 'W1')
        }
    }
}
