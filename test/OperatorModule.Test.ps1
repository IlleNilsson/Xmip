#Requires -Version 7.6.7

# The operator module is built once per change, not once per session
# (Import-XmipOperatorModule): into .local-work/operator/<key>, the key naming
# what it is built from. Until 2026-10-13 every session built it again, and the
# first Write-XmipAudit of Start-XmipTest spent 8.5 of its 9.3 seconds there.
# This holds the key and the reuse decision over a tree of its own; dotnet is
# never run.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # The layout the key reads, with one file in each place and the build
    # output a build leaves under bin/ and obj/.
    function New-OperatorTree {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Name
        )

        [string] $tree = Join-Path -Path $TestDrive -ChildPath $Name
        [string[]] $file = @(
            'module/core/operation/powershell/src/Xmip.PowerShell/Commands.cs'
            'module/core/operation/powershell/src/Xmip.PowerShell/bin/Xmip.PowerShell.dll'
            'module/core/operation/powershell/src/Xmip.PowerShell/obj/project.assets.json'
            'module/foundation/abi/dotnet/Directory.Build.props'
            'module/foundation/abi/dotnet/Xmip.Abi/Operate/Operate.cs'
            'module/foundation/abi/dotnet/Xmip.Surface/RuntimeLibrary.cs'
            '.ai-interaction/target-windows/debug/xmip_core_runtime.dll'
        )

        foreach ($relative in $file) {
            [string] $path = Join-Path -Path $tree -ChildPath $relative
            New-Item -ItemType Directory -Path (Split-Path -Path $path -Parent) -Force |
                Out-Null
            Set-Content -LiteralPath $path -Value $relative -NoNewline
        }

        return $tree
    }
}

Describe 'The key of the operator module build' {
    It 'is the same for an unchanged tree' {
        [string] $tree = New-OperatorTree -Name 'unchanged'

        InModuleScope Xmip -Parameters @{ Tree = $tree } {
            param([string] $Tree)

            [string] $first = Get-XmipOperatorModuleKey -Root $Tree
            $first | Should -Match '^[0-9A-F]{16}$'
            Get-XmipOperatorModuleKey -Root $Tree | Should -Be $first
        }
    }

    It 'changes when <Changed> changes' -ForEach @(
        @{ Changed = 'module/core/operation/powershell/src/Xmip.PowerShell/Commands.cs' }
        @{ Changed = 'module/foundation/abi/dotnet/Directory.Build.props' }
        @{ Changed = 'module/foundation/abi/dotnet/Xmip.Abi/Operate/Operate.cs' }
        @{ Changed = 'module/foundation/abi/dotnet/Xmip.Surface/RuntimeLibrary.cs' }
        @{ Changed = '.ai-interaction/target-windows/debug/xmip_core_runtime.dll' }
    ) {
        [string] $tree = New-OperatorTree -Name "changed-$([guid]::NewGuid().ToString('n'))"

        InModuleScope Xmip -Parameters @{ Tree = $tree; Changed = $Changed } {
            param([string] $Tree, [string] $Changed)

            [string] $before = Get-XmipOperatorModuleKey -Root $Tree
            [string] $path = Join-Path -Path $Tree -ChildPath $Changed

            # The same length, a later write: an edit the size does not show.
            [System.IO.File]::SetLastWriteTimeUtc(
                $path, [System.IO.File]::GetLastWriteTimeUtc($path).AddSeconds(2))

            Get-XmipOperatorModuleKey -Root $Tree | Should -Not -Be $before
        }
    }

    It 'changes when a source file is added' {
        [string] $tree = New-OperatorTree -Name 'added'

        InModuleScope Xmip -Parameters @{ Tree = $tree } {
            param([string] $Tree)

            [string] $before = Get-XmipOperatorModuleKey -Root $Tree
            Set-Content -Value 'x' -LiteralPath (
                Join-Path -Path $Tree -ChildPath 'module/foundation/abi/dotnet/Xmip.Surface/New.cs')

            Get-XmipOperatorModuleKey -Root $Tree | Should -Not -Be $before
        }
    }

    It 'does not change when a build writes under bin/ or obj/' {
        [string] $tree = New-OperatorTree -Name 'built'

        InModuleScope Xmip -Parameters @{ Tree = $tree } {
            param([string] $Tree)

            [string] $before = Get-XmipOperatorModuleKey -Root $Tree
            [string] $project = Join-Path -Path $Tree -ChildPath (
                'module/core/operation/powershell/src/Xmip.PowerShell')
            [string] $binary = Join-Path -Path $project -ChildPath 'bin/Xmip.PowerShell.dll'
            Set-Content -Value 'rebuilt' -LiteralPath $binary
            [string] $assets = Join-Path -Path $project -ChildPath 'obj/project.assets.json'
            Set-Content -Value 'restored' -LiteralPath $assets

            Get-XmipOperatorModuleKey -Root $Tree | Should -Be $before
        }
    }
}

Describe 'Reusing a build of the operator module' {
    It 'reuses a directory holding the binary module and builds one without it' {
        InModuleScope Xmip -Parameters @{ Area = [string] $TestDrive } {
            param([string] $Area)

            [string] $built = Join-Path -Path $Area -ChildPath 'reuse/0123456789ABCDEF'
            Test-XmipOperatorModuleBuild -Directory $built | Should -BeFalse

            New-Item -ItemType Directory -Path $built -Force | Out-Null
            Test-XmipOperatorModuleBuild -Directory $built | Should -BeFalse

            Set-Content -Value 'module' -LiteralPath (Join-Path $built 'Xmip.PowerShell.dll')
            Test-XmipOperatorModuleBuild -Directory $built | Should -BeTrue
        }
    }

    It 'removes earlier builds no session holds, keeps a held one and one in progress' {
        InModuleScope Xmip -Parameters @{ Area = [string] $TestDrive } {
            param([string] $Area)

            [string] $operator = Join-Path -Path $Area -ChildPath 'operator'

            foreach ($name in @('KEEP', 'FREE', 'HELD', 'KEEP.build-1234abcd')) {
                [string] $directory = Join-Path -Path $operator -ChildPath $name
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
                Set-Content -Value $name -LiteralPath (Join-Path $directory 'Xmip.PowerShell.dll')
            }

            # A session that imported a build holds its binary module open.
            [System.IO.FileStream] $held = [System.IO.File]::Open(
                (Join-Path $operator 'HELD/Xmip.PowerShell.dll'), 'Open', 'Read', 'Read')

            try {
                Remove-XmipOperatorModuleBuild -Keep (Join-Path $operator 'KEEP')
            }
            finally {
                $held.Dispose()
            }

            [string[]] $left = @(Get-ChildItem -LiteralPath $operator -Directory |
                    ForEach-Object -MemberName Name | Sort-Object)
            $left | Should -Be @('HELD', 'KEEP', 'KEEP.build-1234abcd')
        }
    }
}

Describe 'The built operator module reads the snapshot under the estate root' {
    It 'climbs from where the build lies, not from the project bin' {
        [hashtable] $given = @{ Area = [string] $TestDrive; Estate = $script:Root }

        InModuleScope Xmip -Parameters $given {
            param([string] $Area, [string] $Estate)

            [string] $tree = Join-Path -Path $Area -ChildPath 'estate'
            [string] $build = Join-Path -Path $tree -ChildPath '.local-work/operator/KEY.build-1'
            New-Item -ItemType Directory -Path $build -Force | Out-Null
            [string] $document = Join-Path -Path $build -ChildPath 'xmip.powershell.toml'
            [string] $shipped = Join-Path -Path $Estate -ChildPath (
                'module/core/operation/powershell/src/Xmip.PowerShell/xmip.powershell.toml')
            Copy-Item -LiteralPath $shipped -Destination $document

            Set-XmipOperatorModuleRoot -Directory $build -Root $tree

            [string] $line = @(Get-Content -LiteralPath $document |
                    Where-Object { $_ -match '^Snapshot\s*=' })[0]
            $line | Should -Be 'Snapshot = "../../../.local-work/playground/C1-snapshot.toml"'
        }
    }
}
