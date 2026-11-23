#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

<#
.SYNOPSIS
    Sending the estate to a test computer as a difference: what changed since
    the last send, never the whole estate read again.

.DESCRIPTION
    The computer keeps a mirror of the estate as last sent, <folder>/mirror
    under that account's home, and this machine keeps the list of what it
    sent, <name>/sent.tsv beside the computer's file: each file's path, size
    and time written. A send walks this tree's metadata alone, the estate's
    one walk (Find-XmipFile, which leaves build output out by what it holds,
    never by its name), packs what is new or changed with tar, copies it with
    scp and names what is gone; the first send, or a mirror that is not there
    any more, sends everything once. OpenSSH's own ssh, scp and tar, which
    Windows carries, and nothing else (the owner, 2026-11-23).

    It was a bash script outside the estate until 2026-11-23, in a folder a
    restart clears.

    Style: doc/governance/powershell-style.md
#>


function Send-XmipTestComputerEstate {
    <#
        .SYNOPSIS
            Brings the computer's mirror to this estate as it is now, and
            says in words how much was sent.

        .PARAMETER Computer
            The computer, from Read-XmipTestComputer.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Computer
    )

    [string] $root = (Get-XmipEstateLayout).Root
    $null = New-Item -ItemType Directory -Path $Computer.State -Force

    # One send to a computer at a time: the mirror there and the list here
    # change together. The system lets go of the lock when its holder ends.
    [System.IO.FileStream] $held = $null

    try {
        $held = [System.IO.File]::Open((Join-Path $Computer.State 'send.lock'), 'OpenOrCreate',
            'ReadWrite', 'None')
    }
    catch [System.IO.IOException] {
        throw ("REFUSED. Another console is sending the estate to $($Computer.Name) now; " +
            'start again when it has.')
    }

    try {
        Send-XmipTestComputerDifference -Computer $Computer -Root $root
    }
    finally {
        $held.Dispose()
    }
}


function Send-XmipTestComputerDifference {
    <#
        .SYNOPSIS
            Send-XmipTestComputerEstate's work, under its lock: the
            difference, packed, copied and received, then the list kept.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Computer,

        [Parameter(Mandatory)]
        [string] $Root
    )

    [string] $listed = Join-Path -Path $Computer.State -ChildPath 'sent.tsv'
    [string[]] $now = @(Get-XmipEstateSent -Root $Root)
    $probe = Invoke-XmipTestComputerShell -Computer $Computer -Asked probe
    Assert-XmipTestComputerAnswer -Computer $Computer -Answer $probe -Doing 'reach it'

    # Everything once where the mirror there, or the list here, is not.
    [bool] $whole = "$($probe.Out)" -notmatch 'held' -or -not (Test-Path -LiteralPath $listed)
    [string[]] $sent = @(if (-not $whole) { Get-Content -LiteralPath $listed })
    $difference = Compare-XmipEstateSent -Sent $sent -Now $now

    [string] $gone = Join-Path -Path $Computer.State -ChildPath 'gone.txt'
    [string] $packed = Join-Path -Path $Computer.State -ChildPath 'send.tar'
    Write-XmipLineFeedFile -Path $gone -Line $difference.Gone
    [string[]] $copied = @('gone.txt')

    if ($difference.Changed.Count -gt 0) {
        [string] $changed = Join-Path -Path $Computer.State -ChildPath 'changed.txt'
        Write-XmipLineFeedFile -Path $changed -Line $difference.Changed
        Push-Location -LiteralPath $Root

        try {
            [string] $said = (& tar -cf $packed -T $changed 2>&1) -join ' '
        }
        finally {
            Pop-Location
        }

        if ($LASTEXITCODE -ne 0) {
            throw "FAILED. tar could not pack what changed for $($Computer.Name): $said"
        }

        $copied += 'send.tar'
    }

    Copy-XmipTestComputerFile -Computer $Computer -Name $copied
    [string] $how = if ($whole) { 'whole' } else { 'difference' }
    $received = Invoke-XmipTestComputerShell -Computer $Computer -Asked receive -Given $how
    Assert-XmipTestComputerAnswer -Computer $Computer -Answer $received -Doing 'receive it'
    Remove-Item -LiteralPath $packed -Force -ErrorAction Ignore
    Write-XmipLineFeedFile -Path $listed -Line $now

    [string] $what = if ($whole) { 'the whole estate, once' } else { 'the difference' }
    Write-Host ("Sent $what to $($Computer.Name): $($difference.Changed.Count) changed, " +
        "$($difference.Gone.Count) gone.")
}


function Get-XmipEstateSent {
    <#
        .SYNOPSIS
            What a send compares: each file of the estate as one line, its
            path from the root with forward slashes, its size and the time it
            was written, tab between.

        .DESCRIPTION
            The estate's one walk, Find-XmipFile, leaves build output, git's
            own folder and the working areas out; a submodule's .git, a file
            naming where its repository is on this machine, is left out too,
            since the copy there is one repository of its own.

        .PARAMETER Root
            The estate's root.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Root
    )

    [string] $full = [System.IO.Path]::GetFullPath($Root)

    Find-XmipFile -Path $full -Filter '*' |
        Where-Object { $_.Name -ne '.git' } |
        ForEach-Object {
            [string] $path = [System.IO.Path]::GetRelativePath($full, $_.FullName).Replace('\', '/')
            "$path`t$($_.Length)`t$($_.LastWriteTimeUtc.Ticks)"
        }
}


function Compare-XmipEstateSent {
    <#
        .SYNOPSIS
            What changed between what was sent and what is now: Changed, the
            paths new or written since, and Gone, the paths sent and not
            there now. Pure.

        .PARAMETER Sent
            The lines last sent, as Get-XmipEstateSent writes them.

        .PARAMETER Now
            The lines now.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Sent,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Now
    )

    [HashSet[string]] $before = [HashSet[string]]::new([string[]] $Sent, [StringComparer]::Ordinal)
    [HashSet[string]] $here = [HashSet[string]]::new([StringComparer]::Ordinal)

    [string[]] $changed = @(
        foreach ($line in $Now) {
            [void] $here.Add($line.Split("`t")[0])

            if (-not $before.Contains($line)) {
                $line.Split("`t")[0]
            }
        }
    )
    [string[]] $gone = @(
        foreach ($line in $Sent) {
            [string] $path = $line.Split("`t")[0]

            if (-not $here.Contains($path)) {
                $path
            }
        }
    )

    return [pscustomobject]@{ Changed = $changed; Gone = $gone }
}


function Copy-XmipTestComputerFile {
    <#
        .SYNOPSIS
            Copies files of the computer's folder here into its folder there,
            with scp; FAILED in words where scp fails.

        .PARAMETER Name
            The files' names, in the computer's folder here.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Computer,

        [Parameter(Mandatory)]
        [string[]] $Name
    )

    # By name from the folder itself: scp reads a drive letter as a host.
    [string[]] $argument = @(Get-XmipTestComputerOption -Computer $Computer) + '-q' + $Name +
        "$($Computer.User)@$($Computer.Host):$($Computer.Folder)/"
    Push-Location -LiteralPath $Computer.State

    try {
        [string] $said = (& scp @argument 2>&1) -join ' '
    }
    finally {
        Pop-Location
    }

    if ($LASTEXITCODE -ne 0) {
        throw "FAILED. scp to $($Computer.Name) exited ${LASTEXITCODE}: $said"
    }
}


function Write-XmipLineFeedFile {
    <#
        .SYNOPSIS
            Writes lines ended by a line feed alone, as the shell and tar on
            the computer read them, whatever this system ends a line with.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Line
    )

    [string] $text = if ($Line.Count -gt 0) { ($Line -join "`n") + "`n" } else { '' }
    [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
}
