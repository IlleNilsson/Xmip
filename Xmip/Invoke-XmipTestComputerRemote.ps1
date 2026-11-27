#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    A test computer's side of -ComputerName: what its pwsh does when this
    computer asks, the same on Linux and macOS.

.DESCRIPTION
    Invoke-XmipTestComputerShell sends the text of this file and the others
    of the computer's side (Get-XmipTestComputerRemoteScript) over ssh, and
    the computer's pwsh runs Invoke-XmipTestComputerRemote: probe, receive,
    start or observe, its exit code the answer. Until 2026-11-27 it was a
    bash script taking util-linux's flock and setsid, GNU's find and xargs
    and /proc, so a test computer was Linux; the owner, 2026-11-27, *Go
    ahead*, of doing them in PowerShell 7.7, which every test computer runs
    (ADR-0028, amendment 2026-11-27):

    - The locks are the estate's one, Lock-XmipFile: <folder>/tree.lock, one
      run in a copy at a time, and ~/slot<n>.lock, a build slot
      (Wait-XmipBuildSlot).
    - A start (Start-XmipTestComputerRun) is held by a process of its own
      (Lock-XmipTestComputerRun), and git runs through the module's one way,
      Invoke-XmipGit, sent with it.
    - A send is received through .NET and tar
      (Receive-XmipTestComputerEstate).
    - rsync stays: macOS 15's is openrsync, which keeps and deletes the same
      paths with the same arguments (tried 2026-11-27).

    Style: doc/governance/powershell-style.md
#>


# The exit codes beside 0 and a failure's: a run holds the copy, refused
# before anything there changed (5); the computer lacks what a test computer
# needs (6); nothing was ever started there (7).
[int] $script:XmipTestComputerBusy = 5
[int] $script:XmipTestComputerLacking = 6
[int] $script:XmipTestComputerAbsent = 7

# What a computer lacking a tool is told, {0} its system and {1} the tools:
# the probe's words, and the ssh command's where pwsh is not there.
[string] $script:XmipTestComputerLack = ('REFUSED. {0} here lacks what a test computer ' +
    'needs: {1}. A test computer is Linux or macOS, with pwsh, rsync, tar and git.')


function Invoke-XmipTestComputerRemote {
    <#
        .SYNOPSIS
            Runs on the test computer: does what -Encoded asks and answers
            the exit code its pwsh exits with.

        .PARAMETER Encoded
            What is asked, a hashtable PowerShell serialized, in base64:
            Asked, probe, receive, start, hold or observe; Folder, under the
            account's home or whole; SlotFolder, where the slots' locks are,
            the home where it is not said; Slots; Work, the working area's
            name (Get-XmipEstateLayout); Given, for receive whole or
            difference, for start and observe the pwsh command, encoded.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Encoded
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    [hashtable] $asked = [Management.Automation.PSSerializer]::Deserialize(
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Encoded)))
    $asked.Folder = [IO.Path]::Combine($HOME, $asked.Folder)

    if (-not $asked.ContainsKey('SlotFolder')) {
        $asked.SlotFolder = $HOME
    }

    [string] $folder = $asked.Folder

    switch ($asked.Asked) {
        'probe' {
            return Test-XmipTestComputerReady -Folder $folder
        }
        'receive' {
            return Receive-XmipTestComputerEstate -Folder $folder -How $asked.Given
        }
        'start' {
            return Start-XmipTestComputerRun -Asked $asked
        }
        'hold' {
            return Lock-XmipTestComputerRun -Asked $asked
        }
        'observe' {
            return Invoke-XmipTestComputerObserve -Folder $folder -Given $asked.Given
        }
    }

    throw "REFUSED. A test computer is asked probe, receive, start or observe: $($asked.Asked)."
}


function New-XmipTestComputerRemoteCommand {
    <#
        .SYNOPSIS
            What pwsh -Command runs on a test computer: each of -Script
            dot-sourced, then Invoke-XmipTestComputerRemote asked -Asked,
            words plain, never colored. Both travel in base64 between double
            quotes, the scripts compressed, so the command holds no single
            quote, a shell takes it whole between two, and ssh's command
            line stays within Windows's 32767 characters.

        .PARAMETER Script
            The files' texts, each dot-sourced alone, as each says what it
            requires.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string[]] $Script,

        [Parameter(Mandatory)]
        [hashtable] $Asked
    )

    [IO.MemoryStream] $packed = [IO.MemoryStream]::new()
    [IO.Compression.GZipStream] $zip = [IO.Compression.GZipStream]::new($packed,
        [IO.Compression.CompressionLevel]::SmallestSize)
    [byte[]] $bytes = [Text.Encoding]::UTF8.GetBytes($Script -join [char] 0)
    $zip.Write($bytes, 0, $bytes.Length)
    $zip.Dispose()
    [string] $text = [Convert]::ToBase64String($packed.ToArray())
    [string] $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
            [Management.Automation.PSSerializer]::Serialize($Asked)))

    return ('$PSStyle.OutputRendering = "PlainText"; foreach ($text in [IO.StreamReader]::new(' +
        '[IO.Compression.GZipStream]::new([IO.MemoryStream]::new([Convert]::FromBase64String(' +
        """$text"")), [IO.Compression.CompressionMode]::Decompress)).ReadToEnd().Split(" +
        '[char] 0)) { . ([scriptblock]::Create($text)) }; ' +
        "exit (Invoke-XmipTestComputerRemote -Encoded ""$encoded"")")
}


function Get-XmipTestComputerRemoteScript {
    <#
        .SYNOPSIS
            The texts a test computer is sent: the files of the computer's
            side and of Lock-XmipFile, each as it was read, line feeds alone,
            each named by a function it defines. Run there, the texts it was
            itself sent, which a start hands its holder.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    [string[]] $text = @(
        foreach ($name in 'Lock-XmipFile', 'Invoke-XmipGit', 'Invoke-XmipTestComputerRemote',
            'Receive-XmipTestComputerEstate', 'Start-XmipTestComputerRun',
            'Lock-XmipTestComputerRun', 'Wait-XmipBuildSlot') {
            [Management.Automation.Language.Ast] $root = (
                Get-Command -Name $name -CommandType Function).ScriptBlock.Ast

            while ($null -ne $root.Parent) {
                $root = $root.Parent
            }

            $root.Extent.Text.Replace("`r`n", "`n")
        }
    )

    return [string[]] @($text | Select-Object -Unique)
}


function Test-XmipTestComputerReady {
    <#
        .SYNOPSIS
            The probe: refuses a computer lacking what a test computer
            needs, naming it, and one whose copy a run holds; otherwise says
            held where the mirror of an earlier send is there, else none.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Folder
    )

    [string[]] $missing = @('rsync', 'tar', 'git' | Where-Object {
            $null -eq (Get-Command -Name $_ -CommandType Application -ErrorAction Ignore)
        })

    if ($missing.Count -gt 0) {
        # Linux or Darwin, as uname -s says it in the ssh command's words.
        [string] $system = [Runtime.InteropServices.RuntimeInformation]::OSDescription.Split(' ')[0]
        [string] $lacking = $script:XmipTestComputerLack -f $system, ($missing -join ', ')
        Write-XmipTestComputerLine -Stream Error -Text $lacking

        return $script:XmipTestComputerLacking
    }

    [IO.FileStream] $held = Lock-XmipTestComputerCopy -Folder $Folder

    if ($null -eq $held) {
        return $script:XmipTestComputerBusy
    }

    try {
        [string] $mirror = Join-Path -Path $Folder -ChildPath 'mirror'
        [bool] $sent = Test-Path -LiteralPath $mirror -PathType Container
        Write-XmipTestComputerLine -Text $(if ($sent) { 'held' } else { 'none' })

        return 0
    }
    finally {
        $held.Dispose()
    }
}


function Lock-XmipTestComputerCopy {
    <#
        .SYNOPSIS
            The copy's lock, <folder>/tree.lock, the folder made where it is
            not, taken by a probe and a receive while they work and by a
            start for its run. $null, refused in words, where a run holds it.
    #>
    [CmdletBinding()]
    [OutputType([IO.FileStream])]
    param(
        [Parameter(Mandatory)]
        [string] $Folder
    )

    $null = New-Item -ItemType Directory -Path $Folder -Force
    [IO.FileStream] $held = Lock-XmipFile -Path (Join-Path -Path $Folder -ChildPath 'tree.lock')

    if ($null -eq $held) {
        [string] $tree = Join-Path -Path $Folder -ChildPath 'xmip'
        Write-XmipTestComputerLine -Stream Error -Text ("REFUSED. A run is going on in ${tree}: " +
            'stop it, or name another computer file with a folder of its own.')
    }

    return $held
}


function Invoke-XmipTestComputerObserve {
    <#
        .SYNOPSIS
            Runs the pwsh command -Given encodes in the copy as it is, no
            lock taken, and answers its exit code; refused where nothing was
            ever started there.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Folder,

        [Parameter(Mandatory)]
        [string] $Given
    )

    [string] $tree = Join-Path -Path $Folder -ChildPath 'xmip'

    if (-not (Test-Path -LiteralPath $tree -PathType Container)) {
        Write-XmipTestComputerLine -Stream Error -Text (
            "REFUSED. Nothing was ever started here: $tree is not there.")

        return $script:XmipTestComputerAbsent
    }

    Set-XmipTestComputerEnvironment -Folder $Folder

    return Start-XmipTestComputerCommand -Tree $tree -Given $Given
}


function Write-XmipTestComputerLine {
    <#
        .SYNOPSIS
            Writes one line to standard output, or to standard error, through
            a stream that fails where nothing reads it any more, as the
            console's own writer does not: a line whose console has gone
            ends what wrote it.

        .PARAMETER Stream
            Output or Error.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter()]
        [ValidateSet('Output', 'Error')]
        [string] $Stream = 'Output'
    )

    [Microsoft.Win32.SafeHandles.SafeFileHandle] $handle = if ($Stream -eq 'Error') {
        [Console]::OpenStandardErrorHandle()
    }
    else {
        [Console]::OpenStandardOutputHandle()
    }
    [IO.FileStream] $writer = [IO.FileStream]::new($handle, [IO.FileAccess]::Write, 1)

    try {
        [byte[]] $line = [Text.Encoding]::UTF8.GetBytes("$Text`n")
        $writer.Write($line, 0, $line.Length)
    }
    finally {
        $writer.Dispose()
    }
}
