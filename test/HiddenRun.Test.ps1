#requires -PSEdition Core
#requires -Version 7.6.5

<#
    A test run can be hidden. The owner, 2026-09-29: *If you need a cluster for
    test purposes that is fine, call it CT. When tests are run it's got to be
    hidable.* Hiding is by what a run declares — Start-XmipTest -Hidden — and
    never by the name of its cluster, since nothing at runtime reads meaning
    from a name (ADR-0028 and ADR-0052, amendments 2026-09-30). These are the
    checks on the tooling's side: the declaration reaches the roll, a hidden
    run is listed only when asked, and a run called CT that declared nothing
    is listed like any other. The suite starts nothing.
#>

BeforeAll {
    $script:AuditBefore = $env:XMIP_AUDIT_DIRECTORY
    $env:XMIP_AUDIT_DIRECTORY = Join-Path -Path $TestDrive -ChildPath 'audit'

    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
}

AfterAll {
    $env:XMIP_AUDIT_DIRECTORY = $script:AuditBefore
}

Describe 'A run declares itself hidden and is listed only when asked' {
    It 'tells the roll it is hidden, and says nothing when it is not' {
        InModuleScope Xmip {
            $least = @{ Stress = 'Calm'; Area = 'a' }

            (New-XmipPlaygroundEnvironment @least -Hidden).XMIP_PLAYGROUND_HIDDEN |
                Should -Be 'true'
            (New-XmipPlaygroundEnvironment @least).Keys |
                Should -Not -Contain 'XMIP_PLAYGROUND_HIDDEN'
        }
    }

    It 'reads the variable the roll reads, from the file that reads it' {
        # environment.rs is the one place the roll reads a variable.
        [string] $roll = Get-Content -Raw -LiteralPath (
            Join-Path $script:Root 'test/core/playground/src/environment.rs')

        $roll | Should -Match 'XMIP_PLAYGROUND_HIDDEN'
    }

    It 'belongs to the Playground alone, and records it in the run record' {
        InModuleScope Xmip {
            $script:XmipPlaygroundOnly | Should -Contain 'Hidden'
        }

        (Get-Command -Name Start-XmipTest).Parameters['Hidden'].ParameterType |
            Should -Be ([switch])
        [string] $roll = Get-Content -Raw -LiteralPath (
            Join-Path $script:Root 'Xmip/Start-XmipPlaygroundRoll.ps1')
        $roll | Should -Match 'hidden\s+= \$hidden'
    }

    It 'lists a hidden run with -IncludeHidden alone, and the others always' {
        InModuleScope Xmip {
            [System.Diagnostics.Process[]] $two = @(
                Get-Process -Id $PID
                Get-Process | Where-Object { $_.Id -notin 0, $PID } | Select-Object -First 1
            )
            $script:Two = $two

            Mock Get-XmipEstateRun { }
            Mock Get-XmipTestNode { }
            Mock Get-XmipPlaygroundProcess { $script:Two }
            Mock Get-XmipRollRecord {
                # The first declared itself hidden; the second declared
                # nothing.
                [bool] $hidden = $Id -eq $script:Two[0].Id
                [PSCustomObject]@{
                    Id     = $Id
                    File   = "roll-$Id.toml"
                    Record = @{
                        suite    = 'Core.Playground'
                        cluster  = if ($hidden) { 'CT' } else { 'C7' }
                        snapshot = 'nowhere-snapshot.toml'
                        hidden   = $hidden
                    }
                }
            }

            [object[]] $shown = @(Get-XmipTestStatus -Path 'a')
            [object[]] $every = @(Get-XmipTestStatus -Path 'a' -IncludeHidden)

            @($shown.Cluster) | Should -Be @('C7')
            @($every.Cluster | Sort-Object) | Should -Be @('C7', 'CT')
            ($every | Where-Object Cluster -EQ 'CT').Hidden | Should -BeTrue
            ($every | Where-Object Cluster -EQ 'C7').Hidden | Should -BeFalse
        }
    }

    It 'lists a cluster called CT that declared nothing like any other' {
        InModuleScope Xmip {
            [System.Diagnostics.Process[]] $one = @(Get-Process -Id $PID)
            $script:One = $one

            Mock Get-XmipEstateRun { }
            Mock Get-XmipTestNode { }
            Mock Get-XmipPlaygroundProcess { $script:One }
            Mock Get-XmipRollRecord {
                [PSCustomObject]@{
                    Id     = $Id
                    File   = "roll-$Id.toml"
                    Record = @{ cluster = 'CT'; snapshot = 'nowhere-snapshot.toml' }
                }
            }

            @(Get-XmipTestStatus -Path 'a').Cluster | Should -Be 'CT'
        }
    }

    It 'stops a hidden run by filter only with -IncludeHidden, and by its id always' {
        InModuleScope Xmip {
            Mock Get-XmipTestStatus {
                [PSCustomObject]@{
                    Id = 21; Kind = 'roll'; State = 'running'; Suite = 'Core.Playground'
                    Cluster = 'CT'; Tests = @(); Hidden = $true; Stress = 'calm'
                }
                [PSCustomObject]@{
                    Id = 22; Kind = 'roll'; State = 'running'; Suite = 'Core.Playground'
                    Cluster = 'C7'; Tests = @(); Hidden = $false; Stress = 'calm'
                }
            }
            Mock Update-XmipPromptFollowing { }
            Import-XmipOperatorModule

            { Stop-XmipTest -Cluster CT -WhatIf -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*REFUSED*No roll matches CT*'
            { Stop-XmipTest -Cluster CT -IncludeHidden -WhatIf -ErrorAction Stop } |
                Should -Not -Throw
            { Stop-XmipTest -Id 21 -WhatIf -ErrorAction Stop } | Should -Not -Throw
        }
    }
}
