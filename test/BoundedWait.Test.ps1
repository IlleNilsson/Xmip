#requires -PSEdition Core
#requires -Version 7.6.5

<#
    A wait with no bound turns a failure into a hang, and a hang has no
    verdict.

    The Playground's own test suite wedged six times running before anyone
    could say why: the process froze at a fixed CPU number with every thread
    in a wait it had asked for, and a landing that should have failed in two
    seconds never finished. The cause was the same line written in a dozen
    places — a `TcpListener::accept()` or a `TcpStream::connect()` with
    nothing bounding it — and a machine out of ephemeral ports, where an
    unanswered connect waits on the operating system's own schedule and an
    accept whose near end never arrived waits for good (2026-09-21).

    A wait may be unbounded on purpose — a real listening Receive Location
    waits as long as it is running — and the helpers that apply a bound
    must call the unbounded primitive in order to poll it. Each such line
    says so on the line directly above it, `// bounded: <why>`, and nothing
    else is exempt: a file cannot be excused wholesale, because a new bare
    call beside a deliberate one would hide behind it. Everything else goes
    through `transport::socket::connect_tcp` and `accept_tcp`. This file is
    how that stays true after the people who fixed it have forgotten.

    Production code only: a file's tests, from its first `#[cfg(test)]` line
    down, may connect however they like. The lines come from
    `Get-XmipSourceFile`, whose `Code` is exactly that boundary.
#>

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'

    Import-Module (Join-Path $script:Root 'Xmip/Xmip.psd1') -Force

    [hashtable] $script:Unbounded = @{
        'a bare connect' = 'TcpStream::connect\('
        'a bare accept'  = '\blistener\s*\.accept\(\)|^\s*\.accept\(\)'
    }

    <#
        .SYNOPSIS
        Every production line in the estate's Rust that waits without a bound.
    #>
    function Find-XmipUnboundedWait {
        [CmdletBinding()]
        [OutputType([string[]])]
        param()

        foreach ($file in @(Get-XmipSourceFile -Root $script:Root -Language Rust)) {
            if ($file.Code -eq 0) {
                continue
            }

            [string] $full = Join-Path $script:Root $file.Path
            [string[]] $line = @(Get-Content -LiteralPath $full -TotalCount $file.Code)

            for ([int] $index = 0; $index -lt $line.Count; $index++) {
                [string] $text = $line[$index]

                if ($text.TrimStart().StartsWith('//')) {
                    continue
                }

                # Deliberate, and said so on the line above.
                if ($index -gt 0 -and $line[$index - 1] -match '//\s*bounded:') {
                    continue
                }

                foreach ($kind in $script:Unbounded.Keys) {
                    if ($text -match $script:Unbounded[$kind]) {
                        "$($file.Path):$($index + 1) is $kind"
                    }
                }
            }
        }
    }

    $script:Found = @(Find-XmipUnboundedWait)
}

Describe 'Every socket wait in the estate has a bound' {
    It 'opens no connection and accepts none except through the transport''s helpers' {
        [string] $detail = $script:Found -join "`n"

        $script:Found.Count | Should -Be 0 -Because (
            "a wait with no bound turns a failure into a hang. Use " +
            "transport::socket::connect_tcp or accept_tcp with the timeout " +
            "in scope:`n$detail"
        )
    }

    It 'finds a bare connect when there is one, so the gate is not silent by accident' {
        # A gate that passes because its pattern matches nothing is worse than
        # no gate. The pattern is asserted against the line it exists to catch.
        'let stream = TcpStream::connect(address)' |
            Should -Match $script:Unbounded['a bare connect']
        '        .accept()' | Should -Match $script:Unbounded['a bare accept']
        'let (s, p) = listener.accept()?;' | Should -Match $script:Unbounded['a bare accept']
        [string] $method = 'pdu::write(&mut w, &accepted.accept())?;'
        $method | Should -Not -Match $script:Unbounded['a bare accept'] -Because (
            'a method named accept is not a socket'
        )
    }
}
