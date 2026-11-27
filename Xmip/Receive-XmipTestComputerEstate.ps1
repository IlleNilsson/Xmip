#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    A test computer receiving a send (Send-XmipTestComputerEstate) into its
    mirror, the same on Linux and macOS.

.DESCRIPTION
    What is gone, and every folder left empty, is taken through .NET, where
    GNU's xargs and find took them until 2026-11-27 (ADR-0028, amendment
    2026-11-27); tar unpacks what changed. Sent to the test computer with
    Invoke-XmipTestComputerRemote's file.

    Style: doc/governance/powershell-style.md
#>


function Receive-XmipTestComputerEstate {
    <#
        .SYNOPSIS
            Receives a send into the mirror, <folder>/mirror: what is gone
            first, then every folder left empty, then what changed, so a
            path that turned from a file into a folder, or back, is taken.
            Refused, changing nothing, where a run holds the copy. Answers
            0, or the refusal's or tar's exit code.

        .PARAMETER How
            whole, the mirror made anew, or difference.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Folder,

        [Parameter(Mandatory)]
        [ValidateSet('whole', 'difference')]
        [string] $How
    )

    [IO.FileStream] $held = Lock-XmipTestComputerCopy -Folder $Folder

    if ($null -eq $held) {
        return $script:XmipTestComputerBusy
    }

    try {
        [string] $mirror = Join-Path -Path $Folder -ChildPath 'mirror'
        [string] $gone = Join-Path -Path $Folder -ChildPath 'gone.txt'
        [IO.FileInfo] $packed = [IO.FileInfo]::new((Join-Path -Path $Folder -ChildPath 'send.tar'))

        if ($How -eq 'whole' -and (Test-Path -LiteralPath $mirror)) {
            Remove-Item -LiteralPath $mirror -Recurse -Force
        }

        $null = New-Item -ItemType Directory -Path $mirror -Force
        Remove-XmipMirrorGone -Mirror $mirror -Gone $gone

        if ($packed.Exists -and $packed.Length -gt 0) {
            & tar -xf $packed.FullName -C $mirror | Out-Host

            if ($LASTEXITCODE -ne 0) {
                return $LASTEXITCODE
            }
        }

        Remove-Item -LiteralPath $packed.FullName, $gone -Force -ErrorAction Ignore

        return 0
    }
    finally {
        $held.Dispose()
    }
}


function Remove-XmipMirrorGone {
    <#
        .SYNOPSIS
            Takes from the mirror each file -Gone names, one path a line,
            then every folder left empty, the deepest first, so a folder
            emptied by another's going goes too.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Mirror,

        [Parameter(Mandatory)]
        [string] $Gone
    )

    [string[]] $named = @(
        if (Test-Path -LiteralPath $Gone -PathType Leaf) {
            [IO.File]::ReadAllLines($Gone) | Where-Object { $_ -ne '' }
        }
    )

    foreach ($path in $named) {
        [string] $file = Join-Path -Path $Mirror -ChildPath $path

        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Remove-Item -LiteralPath $file -Force
        }
    }

    [string[]] $folders = @([IO.Directory]::GetDirectories($Mirror, '*',
            [IO.SearchOption]::AllDirectories) | Sort-Object -Property Length -Descending)

    foreach ($empty in $folders) {
        if ([IO.Directory]::GetFileSystemEntries($empty).Count -eq 0) {
            [IO.Directory]::Delete($empty)
        }
    }
}
