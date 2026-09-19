#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Read-XmipTestNodeCommandLine {
    <#
        .SYNOPSIS
            What a node process was started with, read back from its command
            line: the flags the node binary takes, as a hashtable. Pure.

        .DESCRIPTION
            The node binary (test/playground/src/bin/node.rs) takes
            `--name --shared --stress --rounds --snapshot [--interval-ms]
            [--can] [--online] [--nodes] [--scenarios]`. A running node
            carries nothing else that says what it is, so Get-XmipTestNode
            reads this. Quoted arguments are one token; the executable itself
            is dropped; a flag this does not report is passed over.

            --can is the feature capability the node declared (ADR-0056), in
            the words it takes them: 'receive', 'process,send'. An empty
            value is a node that declared no stage and runs whole tests
            itself; --online is the online capability of the same record.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $CommandLine
    )

    [string[]] $tokens = @(
        [regex]::Matches($CommandLine, '"[^"]*"|\S+') |
            ForEach-Object { $_.Value.Trim('"') }
    )

    [hashtable] $flags = @{
        Name       = $null
        Shared     = $null
        Stress     = $null
        Rounds     = 0
        Snapshot   = $null
        Interval   = [timespan]::FromMilliseconds(250)
        Capability = ''
        Online     = $false
    }

    for ($at = 1; $at + 1 -lt $tokens.Count; $at += 2) {
        [string] $value = $tokens[$at + 1]

        switch ($tokens[$at]) {
            '--name' { $flags.Name = $value }
            '--shared' { $flags.Shared = $value }
            '--stress' { $flags.Stress = $value }
            '--rounds' { $flags.Rounds = [int] $value }
            '--snapshot' { $flags.Snapshot = $value }
            '--interval-ms' { $flags.Interval = [timespan]::FromMilliseconds([int] $value) }
            '--can' { $flags.Capability = $value }
            '--online' { $flags.Online = $value -in 'true', 'yes', 'on', '1' }
        }
    }

    return $flags
}
