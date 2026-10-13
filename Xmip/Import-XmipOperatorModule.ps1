#requires -Version 7.6.5

Set-StrictMode -Version Latest

# The operator module this session loaded for the estate's own use, once.
[System.Management.Automation.PSModuleInfo] $script:XmipOperatorModule = $null

# What the operator module is built from, relative to the estate root: the
# project and the two it references, with the files MSBuild reads beside them.
[string[]] $script:XmipOperatorModuleSource = @(
    'module/core/operation/powershell/global.json'
    'module/core/operation/powershell/src/Xmip.PowerShell'
    'module/foundation/abi/dotnet/Directory.Build.props'
    'module/foundation/abi/dotnet/global.json'
    'module/foundation/abi/dotnet/Xmip.Abi'
    'module/foundation/abi/dotnet/Xmip.Surface'
)

function Get-XmipOperatorModuleKey {
    <#
        .SYNOPSIS
            The key of the operator module's build: sixteen hexadecimal digits
            that change when anything it is built from changes.

        .DESCRIPTION
            Each file Get-XmipOperatorModuleInput returns, by its path, its
            length and its last write: what the directory listing already
            says, so no file is opened. Reading the sources' content cost
            thirty milliseconds a session for nothing an edit, a checkout or a
            cargo link does not already change in the write time. Whole
            columns, not a loop: a PowerShell loop over the files cost thirty
            milliseconds more.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root
    )

    [System.IO.FileInfo[]] $file = Get-XmipOperatorModuleInput -Root $Root
    [string] $listing = (@($file.FullName) -join "`n") + "`n" +
        (@($file.Length) -join "`n") + "`n" + (@($file.LastWriteTimeUtc.Ticks) -join "`n")
    [byte[]] $hash = [System.Security.Cryptography.SHA256]::HashData(
        [System.Text.Encoding]::UTF8.GetBytes($listing))

    return [System.Convert]::ToHexString($hash).Substring(0, 16)
}

function Get-XmipOperatorModuleInput {
    <#
        .SYNOPSIS
            What the operator module is built from, as files: the sources of
            Xmip.PowerShell, Xmip.Surface and Xmip.Abi (bin/ and obj/ aside)
            and the runtime library Xmip.Abi.csproj copies beside them.

        .DESCRIPTION
            Xmip.Abi.csproj chooses the runtime among CARGO_TARGET_DIR's
            debug, the estate's shared build directory and the runtime's own
            target. All three are returned rather than the choice repeated
            here: a change to any of them rebuilds, and MSBuild still chooses.

            In the order the file system lists them, which is the same for a
            directory that has not changed; one that has changes the key
            anyway. Read through .NET alone: it runs before every command
            that needs the operator module, and in a new session every
            PowerShell expression and pipeline costs milliseconds the first
            time it runs.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root
    )

    [System.Collections.Generic.List[System.IO.FileInfo]] $found =
        [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    [System.Collections.Generic.Stack[System.IO.DirectoryInfo]] $pending =
        [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()

    foreach ($source in $script:XmipOperatorModuleSource) {
        [string] $path = [System.IO.Path]::Combine($Root, $source)
        [System.IO.FileInfo] $file = [System.IO.FileInfo]::new($path)

        if ($file.Exists) {
            $found.Add($file)
        }
        elseif ([System.IO.Directory]::Exists($file.FullName)) {
            $pending.Push([System.IO.DirectoryInfo]::new($file.FullName))
        }
    }

    while ($pending.Count -gt 0) {
        [System.IO.DirectoryInfo] $directory = $pending.Pop()
        $found.AddRange($directory.GetFiles())

        foreach ($below in $directory.GetDirectories()) {
            if ($below.Name -cne 'bin' -and $below.Name -cne 'obj') {
                $pending.Push($below)
            }
        }
    }

    # Every file cargo links beside the library is counted too, without the
    # project's exclusions: they are written with it, so they change with it.
    [string[]] $target = @($Root, $Root, $env:CARGO_TARGET_DIR)
    [string[]] $under = @('.ai-interaction/target-windows', 'module/platform/runtime/target', '')

    for ([int] $at = 0; $at -lt $target.Length; $at++) {
        if ([string]::IsNullOrEmpty($target[$at])) {
            continue
        }

        [string] $runtime = [System.IO.Path]::Combine($target[$at], $under[$at], 'debug')

        if ([System.IO.Directory]::Exists($runtime)) {
            [System.IO.DirectoryInfo] $built = [System.IO.DirectoryInfo]::new($runtime)
            $found.AddRange($built.GetFiles('*xmip_core_runtime.*'))
        }
    }

    return [System.IO.FileInfo[]] $found
}

function Test-XmipOperatorModuleBuild {
    <#
        .SYNOPSIS
            True when the directory holds a finished build of the operator
            module, to be imported as it is; false when it must be built.

        .DESCRIPTION
            A build is made beside its directory and moved into it whole, so a
            directory that exists with the binary module in it is finished.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    return [System.IO.File]::Exists((Join-Path -Path $Directory -ChildPath 'Xmip.PowerShell.dll'))
}

function Import-XmipOperatorModule {
    <#
        .SYNOPSIS
            Loads the operator module, Xmip.PowerShell, whose Xmip.Surface
            this module calls for every rule it would otherwise write again.

        .DESCRIPTION
            Code is placed once and everything else uses it (CONTRIBUTING, the
            owner, 2026-09-24). A node's declared capability, a published
            snapshot and the worst leaf are Xmip.Surface's, which calls the
            runtime's own rules (xmip_operate.h section 7), so this module
            reads them through the operator module rather than keeping a copy.

            An operator module already in the session is used as it is.
            Otherwise it is built once per change, not once per session: into
            .local-work/operator/<key>, the key naming what it is built from
            (Get-XmipOperatorModuleKey), and imported from there; a session
            finding that directory imports it in milliseconds. Never from the
            project's bin/, which a loaded module would lock against the next
            build (Test-XmipDotnetModule's reason, 2026-09-03): a change makes
            a new key and the next build a new directory, so no build ever
            writes where a session has loaded. The prompt integration is not
            loaded: only the assemblies are wanted here. Nothing is loaded
            before a command needs it, so a bare machine still imports this
            module and asks what it is missing.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if ($null -ne $script:XmipOperatorModule -or $null -ne (Get-Module -Name 'Xmip.PowerShell')) {
        return
    }

    # Import-Module Xmip -Force forgets the module but not its assembly: .NET
    # never unloads one, and a second of the same name is refused (the owner's
    # console, 2026-09-29). The one already in the process is imported again.
    # A loop, not a pipeline: a new session pays twenty milliseconds for the
    # first Where-Object.
    foreach ($loaded in [System.AppDomain]::CurrentDomain.GetAssemblies()) {
        if ($loaded.GetName().Name -eq 'Xmip.PowerShell') {
            $script:XmipOperatorModule = Import-Module -Assembly $loaded -PassThru -ErrorAction Stop
            return
        }
    }

    [string] $root = Get-XmipRepositoryRoot
    [string] $built = Join-Path -Path $root -ChildPath '.local-work/operator'
    [string] $output = Join-Path -Path $built -ChildPath (Get-XmipOperatorModuleKey -Root $root)

    if (-not (Test-XmipOperatorModuleBuild -Directory $output)) {
        Build-XmipOperatorModule -Root $root -Output $output
    }

    [string] $binary = Join-Path -Path $output -ChildPath 'Xmip.PowerShell.dll'
    $script:XmipOperatorModule = Import-Module -Name $binary -PassThru -ErrorAction Stop
}

function Build-XmipOperatorModule {
    <#
        .SYNOPSIS
            Builds the operator module into Output, whole or not at all, and
            removes the builds of earlier keys no session holds.

        .DESCRIPTION
            Built into a directory of its own beside Output and moved into
            place when done, so a build stopped half way is never taken for a
            finished one, and two sessions building at once both end with one.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Output
    )

    [string] $project = Join-Path -Path $Root -ChildPath (
        'module/core/operation/powershell/src/Xmip.PowerShell/Xmip.PowerShell.csproj')

    if (-not (Get-Command -Name 'dotnet' -ErrorAction SilentlyContinue)) {
        throw ('Xmip reads capabilities and snapshots through the operator module, which ' +
            'needs dotnet to build: Install-XmipPrerequisite -Role developer -Install.')
    }

    [string] $id = [System.Guid]::NewGuid().ToString('n').Substring(0, 8)
    [string] $staging = "$Output.build-$id"
    [string[]] $said = @(& dotnet build $project --output $staging --verbosity quiet --nologo 2>&1)

    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        throw ("The operator module did not build, and Xmip reads capabilities and " +
            "snapshots through it. Run: dotnet build $project`n$($said -join "`n")")
    }

    try {
        [System.IO.Directory]::Move($staging, $Output)
    }
    catch {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue

        # Another session finished the same key first; its build is this one.
        if (-not (Test-XmipOperatorModuleBuild -Directory $Output)) {
            throw
        }
    }

    Remove-XmipOperatorModuleBuild -Keep $Output
}

function Test-XmipOperatorModuleHeld {
    <#
        .SYNOPSIS
            True when a process holds the build's binary module open, as a
            session that imported it does.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    [string] $binary = Join-Path -Path $Directory -ChildPath 'Xmip.PowerShell.dll'

    if (-not [System.IO.File]::Exists($binary)) {
        return $false
    }

    try {
        [System.IO.FileStream] $alone = [System.IO.File]::Open(
            $binary, 'Open', 'ReadWrite', 'None')
        $alone.Dispose()

        return $false
    }
    catch {
        return $true
    }
}

function Remove-XmipOperatorModuleBuild {
    <#
        .SYNOPSIS
            Removes every build of the operator module beside Keep that no
            session holds; one a session has loaded stays, whole.

        .DESCRIPTION
            A build whose binary module some process holds open is a session's
            and stays, since that session still loads the assemblies beside it
            as it needs them; a later build removes it once it is free. A free
            one is renamed out of its key before it is removed, so one that
            cannot be removed entirely is never left under its key missing
            files. A build still in progress (.build-) is another session's
            and is left alone.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Keep
    )

    foreach ($old in @(Get-ChildItem -LiteralPath (Split-Path -Path $Keep -Parent) -Directory)) {
        [string] $gone = $old.FullName

        if ($old.Name -eq (Split-Path -Path $Keep -Leaf) -or $old.Name -like '*.build-*') {
            continue
        }

        if ($old.Name -notlike '*.gone-*') {
            if (Test-XmipOperatorModuleHeld -Directory $old.FullName) {
                continue
            }

            [string] $id = [System.Guid]::NewGuid().ToString('n').Substring(0, 8)
            $gone = "$($old.FullName).gone-$id"

            try {
                [System.IO.Directory]::Move($old.FullName, $gone)
            }
            catch {
                continue
            }
        }

        Remove-Item -LiteralPath $gone -Recurse -Force -ErrorAction SilentlyContinue
    }
}
