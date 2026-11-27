#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The processes a test computer starts: a start's holder, detached, and the
    command a start or an observation runs in the copy, Linux and macOS
    alike.

.DESCRIPTION
    The start ssh runs starts the run's holder (Lock-XmipTestComputerRun) as
    a session of its own, as setsid made one until 2026-11-27 (ADR-0028,
    amendment 2026-11-27), and shows what it says; once the holder says the
    command's exit code, the start ends with it and lets ssh go, and the
    holder stays with the run. Sent to the test computer with
    Invoke-XmipTestComputerRemote's file.

    Style: doc/governance/powershell-style.md
#>


# What a holder writes to the start waiting on it, never shown: a line to
# show and confirm, and the start's exit code once its command has ended.
[string] $script:XmipHolderAsk = 'xmip-ask '
[string] $script:XmipHolderEnded = 'xmip-ended '


function Start-XmipTestComputerRun {
    <#
        .SYNOPSIS
            A start: the run's holder started detached, what it says shown
            as it says it, and the start's exit code answered once its
            command has ended, or the holder's where it ended first, refused
            or failed.

        .PARAMETER Asked
            What Invoke-XmipTestComputerRemote was asked, the folder whole.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Asked
    )

    [hashtable] $holding = $Asked.Clone()
    $holding.Asked = 'hold'
    [hashtable] $made = @{ Script = Get-XmipTestComputerRemoteScript; Asked = $holding }
    [string] $command = New-XmipTestComputerRemoteCommand @made
    [Diagnostics.ProcessStartInfo] $start = [Diagnostics.ProcessStartInfo]::new(
        [Environment]::ProcessPath)

    foreach ($word in '-NoProfile', '-NonInteractive', '-Command', $command) {
        $start.ArgumentList.Add($word)
    }

    $start.StartDetached = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true

    return Read-XmipTestComputerHolder -Holder ([Diagnostics.Process]::Start($start))
}


function Read-XmipTestComputerHolder {
    <#
        .SYNOPSIS
            Shows what the holder says, its errors as errors, until it says
            the start's exit code, which this answers, or ends, answering
            its own. A line that cannot be shown, its console gone, ends
            this, and the holder waiting on it to be shown starts nothing.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [Diagnostics.Process] $Holder
    )

    [IO.StreamReader[]] $from = @($Holder.StandardOutput, $Holder.StandardError)
    [object[]] $reading = @($from[0].ReadLineAsync(), $from[1].ReadLineAsync())

    while ($null -ne $reading[0] -or $null -ne $reading[1]) {
        [Threading.Tasks.Task[]] $pending = @($reading | Where-Object { $null -ne $_ })
        $null = [Threading.Tasks.Task]::WaitAny($pending)

        foreach ($index in 0, 1) {
            if ($null -eq $reading[$index] -or -not $reading[$index].IsCompleted) {
                continue
            }

            [object] $line = $reading[$index].Result
            $reading[$index] = $null

            if ($null -ne $line) {
                [object] $ended = Show-XmipHolderLine -Holder $Holder -Line $line -Index $index

                if ($null -ne $ended) {
                    return $ended
                }

                $reading[$index] = $from[$index].ReadLineAsync()
            }
        }
    }

    $Holder.WaitForExit()

    return $Holder.ExitCode
}


function Show-XmipHolderLine {
    <#
        .SYNOPSIS
            Shows one line the holder said, confirming it where the holder
            asked; answers the start's exit code where the line says it,
            else nothing.

        .PARAMETER Index
            0, said on its standard output; 1, on its standard error.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [Diagnostics.Process] $Holder,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Line,

        [Parameter(Mandatory)]
        [int] $Index
    )

    if ($Index -eq 1) {
        Write-XmipTestComputerLine -Stream Error -Text $Line
    }
    elseif ($Line.StartsWith($script:XmipHolderEnded, [StringComparison]::Ordinal)) {
        return [int] $Line.Substring($script:XmipHolderEnded.Length)
    }
    elseif ($Line.StartsWith($script:XmipHolderAsk, [StringComparison]::Ordinal)) {
        Write-XmipTestComputerLine -Text $Line.Substring($script:XmipHolderAsk.Length)
        $Holder.StandardInput.WriteLine('go')
        $Holder.StandardInput.Flush()
    }
    else {
        Write-XmipTestComputerLine -Text $Line
    }
}


function Start-XmipTestComputerHeld {
    <#
        .SYNOPSIS
            Runs the start's command with the write end of a pipe every
            process it starts inherits, says its exit code to the start
            waiting on it, and reads the pipe to its end: until the run's
            last process has ended. Answers the command's exit code.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Tree,

        [Parameter(Mandatory)]
        [string] $Given
    )

    [IO.Pipes.AnonymousPipeServerStream] $run = [IO.Pipes.AnonymousPipeServerStream]::new(
        [IO.Pipes.PipeDirection]::In, [IO.HandleInheritability]::Inheritable)

    try {
        [int] $code = Start-XmipTestComputerCommand -Tree $Tree -Given $Given
        $run.DisposeLocalCopyOfClientHandle()

        try {
            Write-XmipTestComputerLine -Text "$script:XmipHolderEnded$code"
        }
        catch {
            Write-Verbose -Message "The start's console went; the run is held all the same: $_"
        }

        $null = $run.ReadByte()

        return $code
    }
    finally {
        $run.Dispose()
    }
}


function Start-XmipTestComputerCommand {
    <#
        .SYNOPSIS
            Runs the pwsh command -Given encodes in the copy and answers its
            exit code: pwsh -Command, never -EncodedCommand, which also
            writes what it shows to stderr as CLIXML, shown twice at the
            other end (2026-11-23). It says what it says where this process
            does, and reads nothing.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Tree,

        [Parameter(Mandatory)]
        [string] $Given
    )

    [string] $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Given))
    [Diagnostics.ProcessStartInfo] $start = [Diagnostics.ProcessStartInfo]::new(
        [Environment]::ProcessPath)

    foreach ($word in '-NoProfile', '-NonInteractive', '-Command', $text) {
        $start.ArgumentList.Add($word)
    }

    $start.WorkingDirectory = $Tree
    $start.RedirectStandardInput = $true
    [Diagnostics.Process] $command = [Diagnostics.Process]::Start($start)
    $command.StandardInput.Close()
    $command.WaitForExit()

    return $command.ExitCode
}
