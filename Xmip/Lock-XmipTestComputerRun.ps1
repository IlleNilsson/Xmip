#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    How a test computer holds a run: the copy's lock and a build slot held
    until the run's last process has ended, Linux and macOS alike.

.DESCRIPTION
    The run's holder, started detached by the start ssh runs
    (Start-XmipTestComputerRun), takes the copy's lock, makes the copy,
    takes a build slot (Wait-XmipBuildSlot), runs the command and says its
    exit code, which lets the start and ssh go. The holder stays: .NET's
    lock is no handle a child inherits, as util-linux's flock was until
    2026-11-27, so every process of the run inherits the write end of a pipe
    the holder reads, and its end is the end of the run's last process
    (Start-XmipTestComputerHeld; ADR-0028, amendment 2026-11-27). Sent to
    the test computer with Invoke-XmipTestComputerRemote's file.

    Style: doc/governance/powershell-style.md
#>


function Lock-XmipTestComputerRun {
    <#
        .SYNOPSIS
            The run's holder: takes the copy's lock, makes the copy, takes a
            build slot, runs the command and holds the lock and the slot
            until the run's last process has ended; answers the command's
            exit code, or why nothing started.

        .PARAMETER Asked
            What Invoke-XmipTestComputerRemote was asked, the folder whole.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Asked
    )

    [IO.FileStream] $copy = Lock-XmipTestComputerCopy -Folder $Asked.Folder

    if ($null -eq $copy) {
        return $script:XmipTestComputerBusy
    }

    try {
        [int] $copied = Copy-XmipTestComputerTree -Folder $Asked.Folder -Work $Asked.Work

        if ($copied -ne 0) {
            return $copied
        }

        Set-XmipTestComputerEnvironment -Folder $Asked.Folder
        [hashtable] $wait = @{
            SlotFolder = $Asked.SlotFolder; Slots = $Asked.Slots; Copy = $Asked.Folder
        }
        [IO.FileStream] $slot = Wait-XmipBuildSlot @wait

        # Taken with no start waiting to say so: nothing starts on its own.
        if ($null -eq $slot) {
            return 1
        }

        try {
            [string] $tree = Join-Path -Path $Asked.Folder -ChildPath 'xmip'

            return Start-XmipTestComputerHeld -Tree $tree -Given $Asked.Given
        }
        finally {
            [string] $record = [IO.Path]::ChangeExtension($slot.Name, '.holder')
            Remove-Item -LiteralPath $record -Force -ErrorAction Ignore
            $slot.Dispose()
        }
    }
    finally {
        $copy.Dispose()
    }
}


function Copy-XmipTestComputerTree {
    <#
        .SYNOPSIS
            Makes the copy, <folder>/xmip, the mirror as sent with what runs
            left in it kept, one Git repository of what the estate holds,
            its .gitignore files deciding, since tests read git ls-files;
            answers rsync's exit code. Git's failure throws, in its words.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Folder,

        [Parameter(Mandatory)]
        [string] $Work
    )

    [string] $tree = Join-Path -Path $Folder -ChildPath 'xmip'
    [string[]] $kept = @("/$Work/", '/.git/', 'obj/', 'bin/Debug/', 'bin/Release/', 'node_modules/')
    [string[]] $argument = @('-a', '--delete') + @($kept | ForEach-Object { "--filter=P $_" }) +
        "$(Join-Path -Path $Folder -ChildPath 'mirror')/" + "$tree/"
    $null = New-Item -ItemType Directory -Path $tree -Force
    & rsync @argument > (Join-Path -Path $Folder -ChildPath 'rsync.log')

    if ($LASTEXITCODE -ne 0) {
        return $LASTEXITCODE
    }

    if (-not (Test-Path -LiteralPath (Join-Path -Path $tree -ChildPath '.git'))) {
        $null = Invoke-XmipGit -At $tree -Arguments 'init', '-q'
    }

    $null = Invoke-XmipGit -At $tree -Arguments 'add', '-A'

    return 0
}


function Set-XmipTestComputerEnvironment {
    <#
        .SYNOPSIS
            What a run builds in: the copy's own cargo target; local
            endpoints in the folder, never under /run/user/<uid>, which the
            system removes when the account's last session ends, a detached
            run's ssh among them; that folder named as the user's runtime
            directory where the system has it and nothing named one; and no
            .NET build server outliving its build, holding the slot
            (2026-11-20).
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Folder
    )

    $env:CARGO_TARGET_DIR = Join-Path -Path $Folder -ChildPath 'target'
    [string] $endpoints = Join-Path -Path $Folder -ChildPath 'run'
    [IO.UnixFileMode] $own = 'UserRead, UserWrite, UserExecute'
    $null = [IO.Directory]::CreateDirectory($endpoints, $own)
    $env:XMIP_RUNTIME_DIRECTORY = $endpoints

    if ([string]::IsNullOrEmpty($env:XDG_RUNTIME_DIR)) {
        [string] $runtime = "/run/user/$(& id -u)"

        if (Test-Path -LiteralPath $runtime -PathType Container) {
            $env:XDG_RUNTIME_DIR = $runtime
        }
    }

    $env:MSBUILDDISABLENODEREUSE = '1'
    $env:DOTNET_CLI_USE_MSBUILD_SERVER = '0'
    $env:UseSharedCompilation = 'false'
}
