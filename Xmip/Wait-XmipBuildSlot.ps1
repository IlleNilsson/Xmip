#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    A test computer's build slots, ~/slot<n>.lock, each held by one build at
    a time, Linux and macOS alike.

.DESCRIPTION
    A slot is the estate's one lock (Lock-XmipFile), which util-linux's
    flock took until 2026-11-27. Who holds a slot is its holder's record
    beside it, ~/slot<n>.holder, checked against the processes running,
    where a walk of /proc found every holder (ADR-0028, amendment
    2026-11-27). Sent to the test computer with
    Invoke-XmipTestComputerRemote's file.

    Style: doc/governance/powershell-style.md
#>


function Wait-XmipBuildSlot {
    <#
        .SYNOPSIS
            Takes one of the build slots, ~/slot<n>.lock, as every builder
            there takes one, and answers its lock; waits where every slot is
            taken, saying who holds them once a minute. $null where the
            line saying it was taken found no start waiting on it: nothing
            starts later on its own (the owner, 2026-09-12).

        .PARAMETER Copy
            The copy that builds in it, for its record.
    #>
    [CmdletBinding()]
    [OutputType([IO.FileStream])]
    param(
        [Parameter(Mandatory)]
        [string] $SlotFolder,

        [Parameter(Mandatory)]
        [int] $Slots,

        [Parameter(Mandatory)]
        [string] $Copy
    )

    for ([int] $waited = 0; ; $waited += 5) {
        foreach ($number in 1..$Slots) {
            [string] $path = Join-Path -Path $SlotFolder -ChildPath "slot$number.lock"
            [IO.FileStream] $slot = Lock-XmipFile -Path $path

            if ($null -ne $slot) {
                [string] $taken = "Build slot $number of $Slots taken."

                return Confirm-XmipBuildSlot -Slot $slot -Line $taken -Copy $Copy
            }
        }

        if ($waited % 60 -eq 0) {
            [string] $held = Get-XmipBuildSlotHolder -SlotFolder $SlotFolder -Slots $Slots
            Write-XmipTestComputerLine -Text "Waiting for a build slot:$held"
        }

        Start-Sleep -Seconds 5
    }
}


function Confirm-XmipBuildSlot {
    <#
        .SYNOPSIS
            Writes the slot's record, <slot>.holder: this process, since
            when and -Copy; then has the start show -Line and say it did.
            The slot answered where it did, else let go and $null.
    #>
    [CmdletBinding()]
    [OutputType([IO.FileStream])]
    param(
        [Parameter(Mandatory)]
        [IO.FileStream] $Slot,

        [Parameter(Mandatory)]
        [string] $Line,

        [Parameter(Mandatory)]
        [string] $Copy
    )

    [string] $record = [IO.Path]::ChangeExtension($Slot.Name, '.holder')
    [string] $since = [DateTimeOffset]::Now.ToString('o')
    [IO.File]::WriteAllText($record, "$PID`t$since`t$Copy")
    [bool] $shown = $false

    try {
        Write-XmipTestComputerLine -Text "$script:XmipHolderAsk$Line"
        $shown = [Console]::In.ReadLine() -eq 'go'
    }
    finally {
        if (-not $shown) {
            Remove-Item -LiteralPath $record -Force -ErrorAction Ignore
            $Slot.Dispose()
        }
    }

    if ($shown) {
        return $Slot
    }

    return $null
}


function Get-XmipBuildSlotHolder {
    <#
        .SYNOPSIS
            Who holds each slot, as a waiting start says it: the process,
            how long it has held the slot and the copy it builds, from the
            slot's record where that process still runs; held where nothing
            says who, another builder's or a record whose process ended.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $SlotFolder,

        [Parameter(Mandatory)]
        [int] $Slots
    )

    [string[]] $said = @(
        foreach ($number in 1..$Slots) {
            [string] $record = Join-Path -Path $SlotFolder -ChildPath "slot$number.holder"
            [string] $who = 'held'

            try {
                [string[]] $field = [IO.File]::ReadAllText($record).Split("`t")
                [DateTimeOffset] $since = [DateTimeOffset]::Parse($field[1],
                    [Globalization.CultureInfo]::InvariantCulture)
                [Diagnostics.Process] $process = Get-Process -Id ([int] $field[0]) -ErrorAction Stop

                if ($process.StartTime -le $since.LocalDateTime) {
                    [TimeSpan] $held = [DateTimeOffset]::Now - $since
                    [object[]] $told = @(
                        $process.Id, [Math]::Floor($held.TotalHours), $held, $field[2])
                    $who = '{0}, {1:00}:{2:mm\:ss}, {3}' -f $told
                }
            }
            catch {
                Write-Verbose -Message "slot$number says nothing of who holds it: $_"
            }

            " slot$number, $who;"
        }
    )

    return -join $said
}
