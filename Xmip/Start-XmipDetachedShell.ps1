#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    How every detached run of the tooling starts: a script in a pwsh of its
    own, and the values written into that script.

.DESCRIPTION
    The estate's Pester suite, a roll's build and the demo readiness check each
    run in a pwsh of their own, detached, so the console is the operator's
    meanwhile (the owner, 2026-09-12 and 2026-10-13: nothing starts itself,
    and nothing holds the console). The launch was written out in the first
    two until 2026-11-10, when the third would have been a third copy.

    Style: doc/governance/powershell-style.md
#>


function Start-XmipDetachedShell {
    <#
        .SYNOPSIS
            Starts -Script in `pwsh -NoProfile -NonInteractive
            -EncodedCommand` from this session's $PSHOME, at the estate root,
            with no window on Windows, and returns the process at once.

        .DESCRIPTION
            Encoded, so nothing in the script is read by a command line. Its
            output goes to -Log and its errors beside it, with the extension
            .err. What it starts audits where the tooling does (ADR-0062):
            the audit's directory is set for this session first, and the
            process inherits it.

        .PARAMETER Script
            What the pwsh runs.

        .PARAMETER Log
            Where its output goes.
    #>
    [CmdletBinding()]
    [OutputType([System.Diagnostics.Process])]
    param(
        [Parameter(Mandatory)]
        [string] $Script,

        [Parameter(Mandatory)]
        [string] $Log
    )

    $layout = Get-XmipEssentialsLayout
    [string] $shell = Join-Path -Path $PSHOME -ChildPath "pwsh$($layout.Suffix)"
    [string] $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))

    [hashtable] $launch = @{
        FilePath               = $shell
        ArgumentList           = @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
        WorkingDirectory       = $layout.Root
        RedirectStandardOutput = $Log
        RedirectStandardError  = [System.IO.Path]::ChangeExtension($Log, '.err')
        PassThru               = $true
    }

    if ($IsWindows) {
        $launch.WindowStyle = 'Hidden'
    }

    Initialize-XmipAudit

    return Start-Process @launch
}


function ConvertTo-XmipLiteral {
    <#
        .SYNOPSIS
            A value as a single-quoted PowerShell literal, so a path or a name
            written into a detached run's script is never parsed as code.

        .PARAMETER Text
            The value.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    return "'" + ($Text -replace "'", "''") + "'"
}
