#Requires -Version 7.6.7

# Every System Process Xmip owns, with what it says of itself (ADR-0053).

function Get-XmipProcess {
    <#
        .SYNOPSIS
            Lists every System Process Xmip owns, with the name, the location
            and the purpose each declared.

        .DESCRIPTION
            Every System Process Xmip owns is named xmip or xmip-<what>
            (ADR-0053, amendment 2026-10-22), so the operating system's list
            is the list:

                Get-Process xmip, xmip-* | Stop-Process -Force

            stops them all. This says what each one is for before you do. A
            process declares three things where it starts — its name, its
            location, and its purpose, test or runtime — to one file named for
            it and its pid, and takes the file away where it ends. A process
            that was killed leaves its file behind; this drops it.

            The declarations are read by the node (xmip-core-node), through the
            runtime's library, as the processes write them: this module reads
            no declaration file itself.

            A process that declared nothing is still listed, by its name, with
            Declared false: the name is the rule, the declaration the courtesy.

            A process that publishes a snapshot says where, and Snapshot is
            it: an xmip-service node publishes to snapshot.toml in its data
            directory (ADR-0018, amendment 2026-09-30), so the listing pipes
            into Start-XmipOperationWeb, which binds Snapshot by name.

        .PARAMETER Name
            Only the processes whose name matches, wildcards allowed:
            -Name 'xmip-playground-*' is every roll, cluster and node on this
            machine, and -Name 'xmip-playground-C1-*' is the tree of a
            cluster someone called C1, since a Playground process carries
            its cluster and what it is (ADR-0053, amendment 2026-09-20). Every
            Xmip process unless said.

        .PARAMETER Purpose
            Only the processes that declared this purpose: Test or Runtime.
            Two values and both are offered, so this is a set rather than a
            pattern (ADR-0055 clause 4).

        .PARAMETER Path
            The directory the declarations are in. Omitted, the one the node
            names: XMIP_PROCESS_DIRECTORY, else xmip/process under the system's
            temporary directory.

        .EXAMPLE
            Get-XmipProcess

        .EXAMPLE
            Get-XmipProcess -Purpose Test | Stop-Process -Force

        .EXAMPLE
            Get-XmipProcess -Name 'xmip-playground-C1-*'

        .EXAMPLE
            Get-XmipProcess -Name 'xmip-service*' | Start-XmipOperationWeb
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [SupportsWildcards()]
        [string] $Name = '*',

        [Parameter()]
        [ValidateSet('Test', 'Runtime')]
        [string] $Purpose,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    [hashtable] $declared = Read-XmipProcessDeclaration -Path $Path

    [object[]] $running = @(Get-Process -Name $script:XmipProcessName -ErrorAction SilentlyContinue)

    foreach ($process in $running) {
        if ($process.ProcessName -notlike $Name) {
            continue
        }

        $said = $declared[$process.Id]
        [string] $stated = [string](Get-TomlValue -Node $said -Name 'purpose' -Default '')

        if ($PSBoundParameters.ContainsKey('Purpose') -and $stated -ne $Purpose) {
            continue
        }

        # An elevated process shows no start time to a session that is not.
        $started = try { $process.StartTime } catch { $null }

        [PSCustomObject]@{
            PSTypeName = 'Xmip.Process'
            Name       = $process.ProcessName
            Id         = $process.Id
            Purpose    = if ($stated) { (Get-Culture).TextInfo.ToTitleCase($stated) } else { '' }
            Location   = [string](Get-TomlValue -Node $said -Name 'location' -Default '')
            Snapshot   = [string](Get-TomlValue -Node $said -Name 'snapshot' -Default '')
            Started    = $started
            Declared   = $null -ne $said
        }
    }
}

function Read-XmipProcessDeclaration {
    <#
        .SYNOPSIS
            The declarations standing in a directory, by pid, dropping those
            whose process is gone: a killed process cannot take its own away.

        .DESCRIPTION
            The node reads the files (xmip-core-node, through the runtime's
            library: [Xmip.Surface.ProcessDeclaration]::Standing); this judges
            which processes still run, which only a reader that sees the
            operating system's processes can, and removes the files of the
            ones that do not. Each declaration is a dictionary of what the
            file says — name, location, purpose, pid, started_unix, path, and
            whatever else the process said of itself, such as a Playground
            node's flags — and file, where it stands.

        .PARAMETER Path
            The directory. Omitted or empty, the one the node names.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Path
    )

    Import-XmipOperatorModule

    [hashtable] $byId = @{}

    foreach ($standing in [Xmip.Surface.ProcessDeclaration]::Standing($Path).Processes) {
        $alive = Get-Process -Id $standing.Pid -ErrorAction SilentlyContinue

        if ($null -eq $alive -or -not (Test-XmipProcessName -Name $alive.ProcessName)) {
            Remove-Item -LiteralPath $standing.File -Force -ErrorAction SilentlyContinue
            continue
        }

        $said = [ordered]@{
            name         = $standing.Name
            location     = $standing.Location
            purpose      = $standing.Purpose
            pid          = $standing.Pid
            started_unix = $standing.StartedUnix
            path         = $standing.Path
            file         = $standing.File
        }

        foreach ($entry in $standing.Said.GetEnumerator()) {
            $said[$entry.Key] = $entry.Value
        }

        $byId[$standing.Pid] = $said
    }

    return $byId
}

function Test-XmipProcessName {
    <#
        .SYNOPSIS
            Whether a process name is one Xmip owns: xmip, the command a
            person types, or xmip-<what> (ADR-0053, amendment 2026-10-22).

        .DESCRIPTION
            The one rule, beside the names Get-XmipProcess asks the
            operating system for ($script:XmipProcessName). The owner,
            2026-09-18: "xmip-cli, not xmip: every System Process Xmip owns
            matches xmip-*"; and 2026-10-22: "Xmip CLI should be named just
            xmip". So a forgotten xmip --follow is found and stopped with the
            rest.

        .PARAMETER Name
            The process name, without an extension.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name
    )

    foreach ($pattern in $script:XmipProcessName) {
        if ($Name -like $pattern) {
            return $true
        }
    }

    $false
}
