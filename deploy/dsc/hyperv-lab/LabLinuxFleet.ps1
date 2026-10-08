#requires -PSEdition Core
#requires -Version 7.6.5
# The lab's AlmaLinux guests over SSH: their payload copied to /opt/xmip-lab,
# PowerShell and DSC v3 installed from it, and the guest's own DSC document
# tested or set there. Secrets travel on SSH's standard input to a root-only
# file on the guest's tmpfs, live for the one DSC run, and never enter DSC
# JSON or a command line.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LabGuestRoot = '/opt/xmip-lab'

function Get-LabSshArgument {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab
    )

    [string] $knownHosts = Join-Path -Path (Split-Path -Path $Lab.SshKeyPath -Parent) -ChildPath
        'known_hosts'
    return @(
        '-i', $Lab.SshKeyPath,
        '-o', 'BatchMode=yes',
        '-o', 'IdentitiesOnly=yes',
        '-o', 'StrictHostKeyChecking=accept-new',
        '-o', "UserKnownHostsFile=$knownHosts",
        '-o', 'ConnectTimeout=5'
    )
}

function Invoke-LabSsh {
    <#
    .SYNOPSIS
    Runs one shell command on a Linux guest as the lab account. Returns
    ExitCode, Output (standard output lines) and Error (standard error lines).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [string] $Command,

        [AllowNull()]
        [string] $InputText
    )

    [string[]] $arguments = @(Get-LabSshArgument -Lab $Lab) +
        "$script:LabLinuxUser@$($Machine.Address)" + $Command
    [object[]] $output = if ([string]::IsNullOrEmpty($InputText)) {
        @(& ssh -n @arguments 2>&1)
    }
    else {
        @($InputText | & ssh @arguments 2>&1)
    }
    [int] $exitCode = $LASTEXITCODE
    [type] $errorType = [Management.Automation.ErrorRecord]
    return [pscustomobject] @{
        ExitCode = $exitCode
        Output = [string[]] @($output | Where-Object { $_ -isnot $errorType })
        Error = [string[]] @($output | Where-Object { $_ -is $errorType })
    }
}

function Copy-LabLinuxPayload {
    <#
    .SYNOPSIS
    Stages one guest's payload, copies it to /opt/xmip-lab (root-only), and
    installs PowerShell and DSC v3 from it where they are missing.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [string] $stage = Join-Path -Path $Lab.Root -ChildPath "$($Machine.Name)/payload"
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Ignore
    New-Item -Path $stage -ItemType Directory | Out-Null
    try {
        [string] $linux = Join-Path -Path $PSScriptRoot -ChildPath 'linux'
        Copy-Item -Path (Join-Path -Path $linux -ChildPath '*') -Destination $stage
        [string] $node = Join-Path -Path $PSScriptRoot -ChildPath 'LabXmipNode.ps1'
        Copy-Item -LiteralPath $node -Destination $stage
        [hashtable] $media = Get-LabLinuxMedia -Lab $Lab -Machine $Machine
        foreach ($relative in $media.Keys) {
            [string] $target = Join-Path -Path $stage -ChildPath $relative
            New-Item -Path (Split-Path -Path $target -Parent) -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath $media[$relative] -Destination $target
        }
        [hashtable] $parameters = @{
            parameters = @{ machine = Get-LabLinuxGuestParameter -Lab $Lab -Machine $Machine }
        }
        $parameters | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path -Path $stage -ChildPath 'machine.json')
        Invoke-LabSshChecked -Lab $Lab -Machine $Machine -Command 'rm -rf ~/xmip-lab-payload'
        [string[]] $copy = @(Get-LabSshArgument -Lab $Lab) + '-q' + '-r' + $stage +
            "$script:LabLinuxUser@$($Machine.Address):xmip-lab-payload"
        & scp @copy
        if ($LASTEXITCODE -ne 0) {
            throw "$($Machine.Name): copying the payload failed."
        }
        [string[]] $install = @(
            "sudo rm -rf $script:LabGuestRoot"
            "sudo mv ~/xmip-lab-payload $script:LabGuestRoot"
            "sudo chown -R root:root $script:LabGuestRoot"
            "sudo chmod -R go-rwx $script:LabGuestRoot"
            "command -v pwsh >/dev/null || sudo dnf install -y $script:LabGuestRoot/powershell.rpm"
            "command -v dsc >/dev/null || sudo dnf install -y $script:LabGuestRoot/dsc.rpm"
        )
        Invoke-LabSshChecked -Lab $Lab -Machine $Machine -Command ($install -join ' && ')
    }
    finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Ignore
    }
}

function Invoke-LabSshChecked {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [string] $Command
    )

    [pscustomobject] $result = Invoke-LabSsh -Lab $Lab -Machine $Machine -Command $Command
    if ($result.ExitCode -ne 0) {
        throw "$($Machine.Name): '$Command' failed: $($result.Error -join ' ')"
    }
}

function Invoke-LabLinuxGuest {
    <#
    .SYNOPSIS
    Tests or sets one guest's DSC document on the guest. Returns Ready and
    Findings; a guest that has never been given its payload has one finding.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Test', 'Set')]
        [string] $Operation,

        [AllowNull()]
        [hashtable] $Secret
    )

    [string] $root = $script:LabGuestRoot
    # DSC finds the resource on PATH; DSC_RESOURCE_PATH would hide pwsh from it.
    [string] $dsc = "test -f $root/machine.json && PATH=${root}:/usr/bin:/usr/sbin:/bin:/sbin " +
        "/usr/bin/dsc --trace-level error config --parameters-file $root/machine.json " +
        "$($Operation.ToLowerInvariant()) --file $root/linux.dsc.yaml --output-format json"
    [string] $command = "sudo sh -c '$dsc'"
    [string] $inputText = $null
    if ($Operation -eq 'Set') {
        $command = "sudo sh -c 'umask 077 && mkdir -p /run/xmip-lab && " +
            "cat > /run/xmip-lab/secret.json && $dsc; status=`$?; " +
            "rm -f /run/xmip-lab/secret.json; exit `$status'"
        $inputText = $Secret | ConvertTo-Json -Compress
    }
    [hashtable] $ssh = @{
        Lab = $Lab
        Machine = $Machine
        Command = $command
        InputText = $inputText
    }
    [pscustomobject] $answer = Invoke-LabSsh @ssh
    return ConvertFrom-LabDscResult -Answer $answer -Operation $Operation
}

function ConvertFrom-LabDscResult {
    <#
    .SYNOPSIS
    Reads `dsc config test|set --output-format json` as Ready and Findings.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Answer,

        [Parameter(Mandatory = $true)]
        [string] $Operation
    )

    [hashtable] $document = $null
    try {
        $document = ($Answer.Output -join "`n") | ConvertFrom-Json -AsHashtable
    }
    catch {
        $document = $null
    }
    if ($null -eq $document -or @($document.results).Count -ne 1) {
        [string] $reason = if ($Answer.ExitCode -eq 1 -and $Answer.Error.Count -eq 0) {
            'the payload has not been copied yet.'
        }
        else {
            "DSC $Operation answered no result: $($Answer.Error -join ' ')"
        }
        return [pscustomobject] @{ Ready = $false; Findings = [string[]] @($reason) }
    }
    [hashtable] $result = $document.results[0].result
    [hashtable] $state = if ($result.ContainsKey('actualState')) {
        $result.actualState
    }
    else {
        $result.afterState
    }
    [string[]] $findings = @($state.Findings)
    return [pscustomobject] @{
        Ready = $findings.Count -eq 0 -and $Answer.ExitCode -eq 0
        Findings = $findings
    }
}

function Get-LabLinuxFleetFinding {
    <#
    .SYNOPSIS
    Every Linux guest's findings, a PostgreSQL primary before its standbys;
    with -Configure, each is given its payload again and set.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [AllowNull()]
        [hashtable] $Secret,

        [switch] $Configure
    )

    [object[]] $ordered = @($Lab.Machines | Where-Object Family -eq 'Linux' |
        Sort-Object { if ($_.ContainsKey('StandbyOf')) { 1 } else { 0 } })
    [hashtable] $ready = @{}
    foreach ($machine in $ordered) {
        [object] $vm = Get-VM -Name $machine.Name -ErrorAction SilentlyContinue
        if ($null -eq $vm -or $vm.Notes -ne $Lab.LabId) {
            # Get-LabVirtualMachineFinding has said so; there is no guest to ask.
            continue
        }
        if ($machine.ContainsKey('StandbyOf') -and -not $ready[$machine.StandbyOf]) {
            [string] $primary = $machine.StandbyOf
            Write-Output -InputObject "$($machine.Name): waiting for its primary $primary."
            continue
        }
        if ((Invoke-LabSsh -Lab $Lab -Machine $machine -Command 'true').ExitCode -ne 0) {
            [string] $unreachable = 'SSH unavailable; it may still be installing from its ISO.'
            Write-Output -InputObject "$($machine.Name): $unreachable"
            continue
        }
        [hashtable] $guest = @{ Lab = $Lab; Machine = $machine; Operation = 'Test' }
        if ($Configure) {
            Complete-LabInstallation -Lab $Lab -Machine $machine -Confirm:$false
            # The payload carries the guest's parameters; a changed lab.json
            # reaches the guest only by copying it again, so Set always does.
            Copy-LabLinuxPayload -Lab $Lab -Machine $machine
            $guest.Operation = 'Set'
            $guest.Secret = $Secret
        }
        [pscustomobject] $result = Invoke-LabLinuxGuest @guest
        $ready[$machine.Name] = $result.Ready
        foreach ($finding in $result.Findings) {
            Write-Output -InputObject "$($machine.Name): $finding"
        }
    }
}
