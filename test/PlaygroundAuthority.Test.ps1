#requires -PSEdition Core
#requires -Version 7.6.7

<#
    The Playground tester acts in the web GUI with an operator certificate:
    the roll's host serves https on 127.0.0.1 under the roll's authority, the
    tester presents a certificate from New-XmipCertificate -Operator, and the
    tester directory knows that certificate's subject (the owner,
    2026-10-21; ADR-0009). These hold the authority the Playground keeps, the
    file a tester signs by, and what Start-XmipOperationWeb hands a host over
    a roll. Nothing is started: Start-Process and dotnet are stood in for.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    $script:AuditBefore = $env:XMIP_AUDIT_DIRECTORY
    $env:XMIP_AUDIT_DIRECTORY = Join-Path -Path $TestDrive -ChildPath 'audit'
}

AfterAll {
    $env:XMIP_AUDIT_DIRECTORY = $script:AuditBefore
}

Describe "The Playground's authority" {
    It 'is made once, keeps its anchor, issues the host anew and names itself to sign by' {
        InModuleScope Xmip -Parameters @{ Folder = (Join-Path $TestDrive 'authority') } {
            param($Folder)

            $first = Initialize-XmipPlaygroundAuthority -Folder $Folder -Confirm:$false
            [string] $anchor = Get-Content -Raw -LiteralPath $first.TrustAnchor
            [string] $host1 = Get-Content -Raw -LiteralPath $first.Certificate
            $again = Initialize-XmipPlaygroundAuthority -Folder $Folder -Confirm:$false

            Get-Content -Raw -LiteralPath $again.TrustAnchor | Should -Be $anchor
            Get-Content -Raw -LiteralPath $again.Certificate | Should -Not -Be $host1
            $loader = [System.Security.Cryptography.X509Certificates.X509CertificateLoader]
            $leaf = $loader::LoadCertificateFromFile($again.Certificate)
            $leaf.Subject | Should -Be 'CN=127.0.0.1'
            $leaf.Dispose()
            $again.PrivateKey | Should -Exist

            [string] $signing = Get-Content -Raw -LiteralPath $again.Configuration
            $signing | Should -Match '\[provision\.operator\]\s+authority = "\."'
            $signing | Should -Match '\[service\]'
        }
    }

    It 'writes nothing under -WhatIf' {
        InModuleScope Xmip -Parameters @{ Folder = (Join-Path $TestDrive 'whatif') } {
            param($Folder)

            Initialize-XmipPlaygroundAuthority -Folder $Folder -WhatIf | Should -BeNullOrEmpty
            $Folder | Should -Not -Exist
        }
    }
}

Describe 'A web host over a roll' {
    BeforeEach {
        InModuleScope Xmip {
            [string] $area = (Get-XmipPlaygroundLayout).Area
            $null = New-Item -ItemType Directory -Path $area -Force
            $script:Snapshot = Join-Path $area "xmip-pester-$([guid]::NewGuid().ToString('n')).toml"
            Set-Content -LiteralPath $script:Snapshot -Value '' -NoNewline
            $script:Launched = $null

            Mock -CommandName Start-Process -MockWith {
                $script:Launched = $ArgumentList
                [PSCustomObject]@{ Id = 1 }
            }
            Mock -CommandName dotnet -MockWith { $global:LASTEXITCODE = 0 }
            Mock -CommandName Test-XmipOperationWebAnswering -MockWith { $false }
            Mock -CommandName Initialize-XmipPlaygroundAuthority -MockWith {
                [PSCustomObject]@{
                    Certificate   = 'C:/kept/host.pem'
                    PrivateKey    = 'C:/kept/host.key'
                    TrustAnchor   = 'C:/kept/authority.pem'
                    Configuration = 'C:/kept/operator.toml'
                }
            }
        }
    }

    AfterEach {
        InModuleScope Xmip {
            Remove-Item -LiteralPath $script:Snapshot -Force -ErrorAction SilentlyContinue
        }
    }

    It "is served https under the roll's authority, knowing the tester's subject" {
        InModuleScope Xmip {
            Start-XmipOperationWeb -Snapshot $script:Snapshot -Tester 'alice@example.org'

            [string[]] $said = $script:Launched
            $said | Should -Contain '--Kestrel:Endpoints:Http:Url=https://127.0.0.1:5087'
            $said | Should -Contain '--Xmip:Directory=tester'
            $said | Should -Contain '--Xmip:Tester=CN=alice@example.org'
            $said | Should -Contain '--Xmip:Certificate=C:/kept/host.pem'
            $said | Should -Contain '--Xmip:PrivateKey=C:/kept/host.key'
            $said | Should -Contain '--Xmip:TrustAnchor=C:/kept/authority.pem'
        }
    }

    It 'binds what the call names, and issues nothing for plain http' {
        InModuleScope Xmip {
            Start-XmipOperationWeb -Snapshot $script:Snapshot -Url 'http://127.0.0.1:5099'

            [string[]] $said = $script:Launched
            $said | Should -Contain '--Kestrel:Endpoints:Http:Url=http://127.0.0.1:5099'
            @($said | Where-Object { $_ -like '--Xmip:Certificate=*' }).Count | Should -Be 0
            @($said | Where-Object { $_ -like '--Xmip:Tester=*' }).Count | Should -Be 0
            Should -Invoke -CommandName Initialize-XmipPlaygroundAuthority -Times 0
        }
    }

    It 'starts nothing and issues nothing under -WhatIf' {
        InModuleScope Xmip {
            Start-XmipOperationWeb -Snapshot $script:Snapshot -Tester 'alice' -WhatIf

            Should -Invoke -CommandName Start-Process -Times 0
            Should -Invoke -CommandName Initialize-XmipPlaygroundAuthority -Times 0
        }
    }
}
