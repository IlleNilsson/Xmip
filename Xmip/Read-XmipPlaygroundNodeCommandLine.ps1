#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Read-XmipPlaygroundNodeCommandLine {
    <#
        .SYNOPSIS
            What a node process was started with, read back from its command
            line: the flags the node binary takes, as a hashtable. Pure.

        .DESCRIPTION
            The node binary (test/playground/src/bin/node.rs) takes
            `--name --shared --stress --rounds --snapshot [--interval-ms]
            [--online]`. A running node carries nothing else that says what it
            is, so Get-XmipPlaygroundNode reads this. Quoted arguments are one
            token; the executable itself is dropped.
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
        Name     = $null
        Shared   = $null
        Stress   = $null
        Rounds   = 0
        Snapshot = $null
        Interval = [timespan]::FromMilliseconds(250)
        Online   = $false
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
            '--online' { $flags.Online = $value -in 'true', 'yes', 'on', '1' }
        }
    }

    return $flags
}
