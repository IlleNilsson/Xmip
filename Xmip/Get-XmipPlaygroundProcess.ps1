#requires -Version 7.6.5

Set-StrictMode -Version Latest

# Which live processes are the Playground's. The file on disk is not the
# answer: on 2026-09-19 the owner's roll, its cluster and its nodes were
# alive while Get-XmipTestStatus and Get-XmipTestNode said nothing, because
# the binaries had been rebuilt under the running processes and the lookup
# judged a process by the file it no longer matched. Get-XmipProcess found all
# twenty-one, which says where the truth lives: every System Process Xmip owns
# declares its name, its location, its purpose and the binary it started from
# (ADR-0053). A process Xmip started and cannot find is a process Xmip cannot
# stop, so this finds by declaration first, by name second, and says in words
# when the file and the image disagree (ADR-0055).

function Get-XmipPlaygroundProcess {
    <#
        .SYNOPSIS
            Every live process running one Playground binary: the ones the
            operating system names, and the ones that declared themselves as
            it, whatever has happened to the file since they started.

        .PARAMETER Name
            The process name, wildcards allowed. Since 2026-09-20 a
            Playground process is named for its cluster and what it is —
            xmip-playground-V1-roll, xmip-playground-V1-R1 — so the
            Playground's own callers ask for xmip-playground-* and say which
            of the three with -Kind. xmip-gui-web is named outright.

        .PARAMETER Path
            Where the binary is expected to be. A process whose image is
            elsewhere is still this one's, and it is said. A process running
            one of the Playground's own per-instance images is this one's
            without a word, because nothing else writes that directory.

        .PARAMETER Kind
            Which of the Playground's three: Roll, Cluster or Node. The name
            says it — xmip-playground-<cluster>-roll and -cluster end in the
            word, and anything else under the prefix is a node — so a roll's
            tree is found by kind rather than by twenty names.
    #>
    [CmdletBinding()]
    [OutputType([System.Diagnostics.Process])]
    param(
        [Parameter(Mandatory)]
        [SupportsWildcards()]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [ValidateSet('Roll', 'Cluster', 'Node')]
        [string] $Kind
    )

    [hashtable] $declared = Read-XmipProcessDeclaration -Path (Get-XmipProcessDirectory)
    [System.Collections.Generic.List[int]] $found = @()
    [bool] $byKind = $PSBoundParameters.ContainsKey('Kind')

    foreach ($process in @(Get-Process -Name $Name -ErrorAction SilentlyContinue)) {
        if ($byKind -and (Get-XmipPlaygroundImageKind -Name $process.ProcessName) -ne $Kind) {
            continue
        }

        if (Test-XmipPlaygroundBinary -Process $process -Path $Path -Declared $declared) {
            $found.Add($process.Id)
            $process
        }
    }

    # A process the operating system no longer calls by this name, because the
    # file its image came from was renamed or replaced under it. It said what
    # it was where it started, and that is what it still is.
    foreach ($id in @($declared.Keys)) {
        [string] $said = [string] $declared[$id]['name']

        if ($found.Contains([int] $id) -or $said -notlike $Name) {
            continue
        }

        if ($byKind -and (Get-XmipPlaygroundImageKind -Name $said) -ne $Kind) {
            continue
        }

        $process = Get-Process -Id ([int] $id) -ErrorAction SilentlyContinue

        if ($null -eq $process) {
            continue
        }

        Write-Warning (
            "Process $id declared itself as $said; this machine now calls it " +
            "$($process.ProcessName), so its binary changed under it. It is listed, " +
            'so it can be stopped (ADR-0053).'
        )

        $found.Add([int] $id)
        $process
    }
}

function Test-XmipPlaygroundBinary {
    <#
        .SYNOPSIS
            Whether a process is the named Xmip binary — its own build where
            that can be shown, and never dropped for a file that changed
            underneath it.

        .PARAMETER Process
            The process to judge.

        .PARAMETER Path
            The binary it is expected to be running.

        .PARAMETER Declared
            The declarations by pid, from Read-XmipProcessDeclaration, when
            the caller has already read them. Read here otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [hashtable] $Declared
    )

    if ($null -eq $Declared) {
        $Declared = Read-XmipProcessDeclaration -Path (Get-XmipProcessDirectory)
    }

    $said = $Declared[$Process.Id]

    [string] $started = if ($null -ne $said -and $said.Contains('path')) {
        [string] $said['path']
    }
    else {
        ''
    }

    [string] $image = try { $Process.Path } catch { '' }

    # A process running one of the Playground's own per-instance images is the
    # Playground's, and nothing about it disagrees: the image is not the built
    # binary on purpose, because a process name is its image's name and an
    # operator asked to read the cluster and the node off it (ADR-0053,
    # amendment 2026-09-20). Nothing but this module writes that directory.
    if ((Test-XmipPlaygroundOwnImage -Path $started) -or
        (Test-XmipPlaygroundOwnImage -Path $image)) {
        return $true
    }

    [hashtable] $judgment = @{
        Id       = $Process.Id
        Name     = $Process.ProcessName
        Image    = $image
        Declared = $started
        Expected = $Path
    }

    return Test-XmipPlaygroundImage @judgment
}

function Test-XmipPlaygroundImage {
    <#
        .SYNOPSIS
            The judgment itself, over what a process says of itself: the
            binary it declared it started from, the image this machine reports
            it running, and the name it goes by, against the binary expected.

        .DESCRIPTION
            Either path matching the expected binary settles it. Otherwise the
            name is the rule — every System Process Xmip owns is named
            xmip-<what> and nothing else is (ADR-0053) — and the disagreement
            is said in words rather than answered with silence, which is what
            made a roll of twenty-one processes invisible to every cmdlet
            meant to manage it.

        .PARAMETER Id
            The process id, for the words.

        .PARAMETER Name
            The name the process goes by.

        .PARAMETER Image
            The image this machine reports it running; empty where an
            elevated process shows none to this session.

        .PARAMETER Declared
            The binary it declared it started from; empty where it declared
            nothing.

        .PARAMETER Expected
            The binary it is expected to be running.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [int] $Id,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Image,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Declared,

        [Parameter(Mandatory)]
        [string] $Expected
    )

    if ((Test-XmipSamePath -Left $Declared -Right $Expected) -or
        (Test-XmipSamePath -Left $Image -Right $Expected)) {
        return $true
    }

    # Its name vouches for it. A process another session started elevated
    # shows no image to this one (2026-09-14: the owner's roll was invisible
    # to the assistant's shell; 2026-09-18: so was his web host, which
    # Stop-XmipOperationWeb then could not stop).
    if ($Name -notlike 'xmip-*') {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($Image)) {
        Write-Warning (
            "$Name $Id runs $Image rather than ${Expected}: its binary was rebuilt, " +
            'renamed or moved after it started. It is kept, because a process Xmip ' +
            'cannot find is a process Xmip cannot stop.'
        )
    }

    return $true
}

function Test-XmipSamePath {
    <#
        .SYNOPSIS
            Whether two paths name one file. Neither being empty is not a
            match, and a path this session cannot resolve is not one either.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Left,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Right
    )

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return $false
    }

    try {
        return [System.IO.Path]::GetFullPath($Left) -ieq [System.IO.Path]::GetFullPath($Right)
    }
    catch {
        return $false
    }
}

function Resolve-XmipProcessName {
    <#
        .SYNOPSIS
            What a process id is called: the name it declared (ADR-0053),
            else the name this machine lists it under. Never the name of the
            file its image came from, which a rebuild changes underneath a
            running process and which left a roll's nodes with no parent, and
            so unstoppable by their own cmdlet (2026-09-19).

        .PARAMETER Id
            The process id to name. Zero, or a process that has gone, is an
            empty name.

        .PARAMETER Declared
            The declarations by pid, from Read-XmipProcessDeclaration.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int] $Id,

        [Parameter()]
        [hashtable] $Declared
    )

    if ($Id -le 0) {
        return ''
    }

    if ($null -ne $Declared -and $Declared.ContainsKey($Id)) {
        return [string] $Declared[$Id]['name']
    }

    $process = Get-Process -Id $Id -ErrorAction SilentlyContinue

    if ($null -eq $process) {
        return ''
    }

    return $process.ProcessName
}
