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
