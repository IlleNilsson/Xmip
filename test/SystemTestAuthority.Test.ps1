#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The System Tests tester acts in the web GUI with an operator certificate:
    the roll's host serves https on 127.0.0.1 under the roll's authority, the
    tester presents a certificate from New-XmipCertificate -Operator, and the
    tester directory knows that certificate's subject (the owner,
    2026-10-21; ADR-0009). These hold the authority the System Tests keep, the
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

Describe "The System Tests' authority" {
    It 'is made once, keeps its anchor, issues the host anew and names itself to sign by' {
        [string] $area = Join-Path -Path $TestDrive -ChildPath 'system-test'
        InModuleScope Xmip -Parameters @{
            Folder = (Join-Path -Path $area -ChildPath 'authority')
            Area   = $area
            Phone  = (Join-Path -Path $TestDrive -ChildPath 'phone')
        } {
            param($Folder, $Area, $Phone)

            $first = Initialize-XmipSystemTestAuthority -Folder $Folder -Confirm:$false
            [string] $anchor = Get-Content -Raw -LiteralPath $first.TrustAnchor
            [string] $host1 = Get-Content -Raw -LiteralPath $first.Certificate
            $again = Initialize-XmipSystemTestAuthority -Folder $Folder -Confirm:$false

            Get-Content -Raw -LiteralPath $again.TrustAnchor | Should -Be $anchor
            Get-Content -Raw -LiteralPath $again.Certificate | Should -Not -Be $host1
            $loader = [System.Security.Cryptography.X509Certificates.X509CertificateLoader]
            $leaf = $loader::LoadCertificateFromFile($again.Certificate)
            $leaf.Subject | Should -Be 'CN=127.0.0.1'
            $leaf.Dispose()
            $again.PrivateKey | Should -Exist

            # The slice of the node the cluster's file declares the table for,
            # signed by this authority, beside its folder (ADR-0031, amendment
            # 2026-11-19).
            $again.Configuration | Should -Be (Join-Path -Path $Area -ChildPath 'operator.xmip')
            [string] $signing = Get-Content -Raw -LiteralPath $again.Configuration
            $signing | Should -Match '\[provision\.operator\]\s+authority = "authority"'
            $signing | Should -Match '\[signature\]'

            # A tester's request is signed by it, and by nothing edited by hand.
            $certificates = [Xmip.Surface.RuntimeLibrary]::Rules.Certificates
            [string] $key = ''
            [string] $request = ''
            [string] $chain = ''
            [string] $refused = ''
            $certificates.Request('alice@example.org', $Phone, [ref] $key, [ref] $request,
                [ref] $refused) | Should -BeTrue -Because $refused
            [string] $asked = Get-Content -Raw -LiteralPath $request
            $certificates.Sign($again.Configuration, $asked, [ref] $chain, [ref] $refused) |
                Should -BeTrue -Because $refused
            Set-Content -LiteralPath $again.Configuration -NoNewline -Value $signing.Replace(
                'authority = "authority"', "authority = `"authority`"`nlifetime = `"876000h`"")
            $certificates.Sign($again.Configuration, $asked, [ref] $chain, [ref] $refused) |
                Should -BeFalse
            $refused | Should -BeLike '*changed after it was signed*'
        }
    }

    It 'refuses a folder the trust does not read beside a slice' {
        [string] $folder = Join-Path -Path $TestDrive -ChildPath 'kept'
        InModuleScope Xmip -Parameters @{ Folder = $folder } {
            param($Folder)

            { Initialize-XmipSystemTestAuthority -Folder $Folder -Confirm:$false } |
                Should -Throw -ExpectedMessage '*not named authority*'
            $Folder | Should -Not -Exist
        }
    }

    It 'writes nothing under -WhatIf' {
        [string] $folder = Join-Path -Path $TestDrive -ChildPath 'whatif/authority'
        InModuleScope Xmip -Parameters @{ Folder = $folder } {
            param($Folder)

            Initialize-XmipSystemTestAuthority -Folder $Folder -WhatIf | Should -BeNullOrEmpty
            $Folder | Should -Not -Exist
        }
    }
}

Describe 'A web host over a roll' {
    BeforeEach {
        InModuleScope Xmip {
            [string] $area = (Get-XmipSystemTestLayout).Area
            $null = New-Item -ItemType Directory -Path $area -Force
            $script:Snapshot = Join-Path $area "xmip-pester-$([guid]::NewGuid().ToString('n')).xmip"
            Set-Content -LiteralPath $script:Snapshot -Value '' -NoNewline
            $script:Launched = $null

            Mock -CommandName Start-Process -MockWith {
                $script:Launched = $ArgumentList
                [PSCustomObject]@{ Id = 1 }
            }
            Mock -CommandName dotnet -MockWith { $global:LASTEXITCODE = 0 }
            Mock -CommandName Test-XmipOperationWebAnswering -MockWith { $false }
            Mock -CommandName Initialize-XmipSystemTestAuthority -MockWith {
                [PSCustomObject]@{
                    Certificate   = 'C:/kept/host.pem'
                    PrivateKey    = 'C:/kept/host.key'
                    TrustAnchor   = 'C:/kept/authority.pem'
                    Configuration = 'C:/kept/operator.xmip'
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
            Should -Invoke -CommandName Initialize-XmipSystemTestAuthority -Times 0
        }
    }

    It 'starts nothing and issues nothing under -WhatIf' {
        InModuleScope Xmip {
            Start-XmipOperationWeb -Snapshot $script:Snapshot -Tester 'alice' -WhatIf

            Should -Invoke -CommandName Start-Process -Times 0
            Should -Invoke -CommandName Initialize-XmipSystemTestAuthority -Times 0
        }
    }
}
