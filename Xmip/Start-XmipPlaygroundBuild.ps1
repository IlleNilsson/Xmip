#requires -PSEdition Core
#requires -Version 7.6.7

<#
.SYNOPSIS
    Building and spawning a Playground roll detached, in a pwsh of its own.

.DESCRIPTION
    Start-XmipTest built the roll in the console until 2026-10-13, and a first
    build held it for minutes. The owner, that day, of Start-XmipTest holding
    his console during the first build: the build runs detached too, as the
    estate's Pester suite has since 2026-09-25 — Start starts, Get-XmipTestStatus
    observes, Stop-XmipTest stops (the owner, 2026-09-12: nothing starts
    itself). What reads a build's record is Get-XmipPlaygroundBuild.ps1; what
    spawns the roll once built is Start-XmipPlaygroundRollProcess.ps1.

    Style: doc/governance/powershell-style.md
#>


function Start-XmipPlaygroundBuild {
    <#
        .SYNOPSIS
            Starts the build and spawn of one roll in a pwsh of its own,
            detached, writes its build record, and returns its pid at once.

        .DESCRIPTION
            What the console decided is handed over as one file,
            build-<start time>.clixml, which the build reads and deletes
            first. Its output — cargo's lines among it — goes to
            build-<start time>.log beside the record, where
            Get-XmipPlaygroundBuild reads how far it has come.

        .PARAMETER Start
            What Start-XmipPlaygroundRoll decided, as
            Start-XmipPlaygroundRollProcess takes it, with Snapshot: where the
            roll will publish, or empty when that is not known yet.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Start
    )

    $layout = Get-XmipPlaygroundLayout
    [string] $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    [string] $stem = Join-Path -Path $Start.Path -ChildPath "build-$stamp"
    [string] $record = "$stem.toml"
    [string] $handed = "$stem.clixml"
    $Start.Log = "$stem.log"

    Export-Clixml -LiteralPath $handed -InputObject $Start -Depth 5

    [string] $shell = Join-Path -Path $PSHOME -ChildPath "pwsh$($layout.Suffix)"
    [string] $script = New-XmipPlaygroundBuildCommand -Record $record -Handed $handed
    [string] $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))

    [hashtable] $launch = @{
        FilePath               = $shell
        ArgumentList           = @('-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded)
        WorkingDirectory       = $layout.Root
        RedirectStandardOutput = $Start.Log
        RedirectStandardError  = "$stem.err"
        PassThru               = $true
    }

    if ($IsWindows) {
        $launch.WindowStyle = 'Hidden'
    }

    # What it starts audits where the tooling does (ADR-0062).
    Initialize-XmipAudit
    $process = Start-Process @launch

    # Written only where the build has not already written its own: a record
    # that cannot be clobbered never relies on the build being slower.
    [hashtable] $began = @{ Start = $Start; Id = $process.Id; Started = $process.StartTime }
    $written = New-XmipPlaygroundBuildRecord @began

    try {
        Write-XmipToml -Path $record -Value $written -NoClobber
    }
    catch {
        Write-Verbose "the build wrote $record before its start was recorded; its own stands"
    }

    return $process.Id
}


function New-XmipPlaygroundBuildCommand {
    <#
        .SYNOPSIS
            The script a detached build executes in its own pwsh.

        .DESCRIPTION
            Every value is written into it as a single-quoted literal, so no
            path is ever parsed as code. Every stream is merged into the
            output, which Start-Process sends to the build's log.

        .PARAMETER Record
            The build record's path.

        .PARAMETER Handed
            The handed-over start's path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Record,

        [Parameter(Mandatory)]
        [string] $Handed
    )

    [scriptblock] $quote = { param([string] $Text) "'" + ($Text -replace "'", "''") + "'" }
    [string] $manifest = & $quote (Join-Path -Path $PSScriptRoot -ChildPath 'Xmip.psd1')

    return @(
        '$ErrorActionPreference = ''Stop'''
        "Import-Module -Name $manifest"
        '& (Get-Module -Name Xmip | Select-Object -First 1) {'
        '    param([string] $Record, [string] $Handed)'
        '    Complete-XmipPlaygroundBuild -Record $Record -Handed $Handed -Verbose'
        "} $(& $quote $Record) $(& $quote $Handed) *>&1 | ForEach-Object { `"`$_`" }"
    ) -join [Environment]::NewLine
}


function New-XmipPlaygroundBuildRecord {
    <#
        .SYNOPSIS
            A build record: what was started, by which pid, and when.

        .PARAMETER Start
            What Start-XmipPlaygroundRoll decided, with Snapshot and Log.

        .PARAMETER Id
            The build's process id.

        .PARAMETER Started
            When the build's process started.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Start,

        [Parameter(Mandatory)]
        [int] $Id,

        [Parameter(Mandatory)]
        [datetime] $Started
    )

    # Read by key: a key a caller left out is empty, never an error.
    return [ordered]@{
        suite    = [string] $Start['Suite']
        cluster  = [string] $Start['Cluster']
        pid      = $Id
        started  = $Started.ToUniversalTime().ToString('o')
        stress   = ([string] $Start['Stress']).ToLowerInvariant()
        tests    = @($Start['Test'] | Where-Object { $null -ne $_ })
        rounds   = [int] $Start['Rounds']
        nodes    = @($Start['Nodes'] | Where-Object { $null -ne $_ })
        online   = @($Start['OnlineNodes'] | Where-Object { $null -ne $_ })
        snapshot = [string] $Start['Snapshot']
        log      = [string] $Start['Log']
        hidden   = [bool] $Start['Hidden']
    }
}


function Complete-XmipPlaygroundBuild {
    <#
        .SYNOPSIS
            What a detached build does in its own pwsh: build the binaries,
            spawn the roll, and leave the record to the roll — or write into
            it why the build FAILED.

        .DESCRIPTION
            Called by the build itself, never by the console that started it.
            The whole record is written from what the build knows, as
            Complete-XmipEstateRun writes an estate run's, so the two never
            race over reading one file.

        .PARAMETER Record
            The build record's path.

        .PARAMETER Handed
            The handed-over start's path; read and deleted first.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Record,

        [Parameter(Mandatory)]
        [string] $Handed
    )

    [hashtable] $start = Import-Clixml -LiteralPath $Handed
    Remove-Item -LiteralPath $Handed -Force

    try {
        Invoke-XmipPlaygroundBuild -Binary roll | Out-Null
        [int] $roll = Start-XmipPlaygroundRollProcess -Start $start
        Remove-Item -LiteralPath $Record -Force -ErrorAction SilentlyContinue
        Write-Verbose "built; cluster $($start.Cluster) rolls as pid $roll"
    }
    catch {
        [datetime] $began = (Get-Process -Id $PID).StartTime
        $written = New-XmipPlaygroundBuildRecord -Start $start -Id $PID -Started $began
        $written.state = 'FAILED'
        $written.fault = $_.Exception.Message
        $written.finished = [datetime]::UtcNow.ToString('o')
        Write-XmipToml -Path $Record -Value $written
        Write-Verbose "FAILED: $($_.Exception.Message)"
    }
}
