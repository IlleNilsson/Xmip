# One Xmip node of the lab, inside its guest: Windows PowerShell through
# PowerShell Direct on Windows, PowerShell 7 under DSC v3 on Linux, so this
# file keeps to what both run. It places the lab cluster's xmip.toml and the
# program the host staged, and writes the node's configuration as
# `xmip-service --slice` prints it: xmip-core-configure's one slicing, never
# one of the lab's (deployment-model.md section 8). The roles the node
# declares are the cluster file's.
[CmdletBinding()]
[OutputType([string])]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Get', 'Set')]
    [string] $Operation,

    # The node's installation: C:\ProgramData\Xmip or /opt/xmip.
    [Parameter(Mandatory = $true)]
    [string] $Root,

    # Where the host staged xmip.toml and the program.
    [Parameter(Mandatory = $true)]
    [string] $Payload,

    # The program's file name on this operating system.
    [Parameter(Mandatory = $true)]
    [string] $Executable,

    # The node's key under [nodes] in the cluster's file.
    [Parameter(Mandatory = $true)]
    [string] $Node
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[string[]] $leaves = @('bin', 'config', 'modules', 'data', 'logs')
[string] $program = Join-Path -Path (Join-Path -Path $Root -ChildPath 'bin') -ChildPath $Executable
[string] $config = Join-Path -Path $Root -ChildPath 'config'
[string] $cluster = Join-Path -Path $config -ChildPath 'xmip.toml'
[string] $slice = Join-Path -Path $config -ChildPath 'xmip-node.toml'
[hashtable] $staged = @{
    $program = Join-Path -Path $Payload -ChildPath $Executable
    $cluster = Join-Path -Path $Payload -ChildPath 'xmip.toml'
}

function Test-LabSameFile {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Reference
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    [string[]] $hashes = @(foreach ($file in @($Path, $Reference)) {
        [Security.Cryptography.SHA256] $sha = [Security.Cryptography.SHA256]::Create()
        try {
            [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($file)))
        }
        finally {
            $sha.Dispose()
        }
    })
    return $hashes[0] -eq $hashes[1]
}

function Get-LabSlice {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Windows PowerShell stops on a native command's standard error under Stop;
    # the refusal is read from the exit code and said whole below.
    $ErrorActionPreference = 'Continue'
    [string[]] $lines = @(& $program --configuration $cluster --node $Node --slice 2>&1 |
        ForEach-Object { [string] $_ })
    if ($LASTEXITCODE -ne 0) {
        throw "xmip-service --slice refused the node $($Node): $($lines -join ' ')"
    }
    return ($lines -join "`n") + "`n"
}

if (-not (Test-Path -LiteralPath $Payload -PathType Container)) {
    return 'The Xmip payload is not staged on this machine.'
}
if ($Operation -eq 'Set') {
    foreach ($leaf in $leaves) {
        New-Item -Path (Join-Path -Path $Root -ChildPath $leaf) -ItemType Directory -Force |
            Out-Null
    }
    foreach ($target in $staged.Keys) {
        if (-not (Test-LabSameFile -Path $target -Reference $staged[$target])) {
            Copy-Item -LiteralPath $staged[$target] -Destination $target -Force
        }
    }
    if ([Environment]::OSVersion.Platform -eq 'Unix') {
        & chmod 0755 $program
    }
    [System.Text.Encoding] $utf8 = New-Object -TypeName Text.UTF8Encoding -ArgumentList $false
    try {
        [IO.File]::WriteAllText($slice, (Get-LabSlice), $utf8)
    }
    catch {
        # A refused slice is this node's finding below, in xmip-service's words.
        Remove-Item -LiteralPath $slice -Force -ErrorAction SilentlyContinue
    }
}
foreach ($leaf in $leaves) {
    [string] $directory = Join-Path -Path $Root -ChildPath $leaf
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        Write-Output -InputObject "Xmip directory is missing: $leaf"
    }
}
foreach ($target in $staged.Keys) {
    if (-not (Test-LabSameFile -Path $target -Reference $staged[$target])) {
        Write-Output -InputObject "Xmip file differs from the lab's: $target"
        return
    }
}
try {
    [string] $expected = Get-LabSlice
    if (-not (Test-Path -LiteralPath $slice -PathType Leaf) -or
        [IO.File]::ReadAllText($slice) -ne $expected) {
        Write-Output -InputObject "The node's xmip-node.toml is not its slice of xmip.toml."
    }
}
catch {
    Write-Output -InputObject $_.Exception.Message
}
