#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The estate's one exclusive lock on a file: what a deployment's run, a send
    to a test computer, and that computer's copy and build slots are held by.

.DESCRIPTION
    A file opened sharing nothing: on Windows a sharing violation, on Linux
    and macOS an flock .NET takes, util-linux's flock's own; either is let go
    when the stream is disposed or the process ends, however it ends.
    Lock-XmipDeployState and Send-XmipTestComputerEstate take theirs here, and
    a test computer is sent this file's text with its side's
    (Invoke-XmipTestComputerRemote), so the lock there is this one. Until
    2026-11-27 the first two each opened theirs and the test computer's shell
    took util-linux's, which macOS lacks (ADR-0028, amendment 2026-11-27).

    Style: doc/governance/powershell-style.md
#>


function Lock-XmipFile {
    <#
        .SYNOPSIS
            The file at -Path, made where it is not, open for this process
            alone until the stream answered is disposed; $null where another
            holds it.

        .DESCRIPTION
            A folder that is not there, or a file this account may not open,
            is an error, never another holder.

        .PARAMETER Path
            The lock's file.
    #>
    [CmdletBinding()]
    [OutputType([IO.FileStream])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    try {
        return [IO.FileStream]::new($Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None)
    }
    catch {
        [Exception] $failure = $_.Exception

        while ($failure -is [Management.Automation.MethodInvocationException] -and
            $null -ne $failure.InnerException) {
            $failure = $failure.InnerException
        }

        # Not found, a folder or a file, derives from IOException and is no
        # other holder.
        if ($failure.GetType() -ne [IO.IOException]) {
            throw
        }

        return $null
    }
}
