#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Invoke-XmipDeployPlaybook {
    <#
        .SYNOPSIS
            Runs deploy/dsc/ansible/environment.yml over the inventory the
            environment file wrote, -Check with --check --diff, and answers
            each host's recap: in its desired state where it was reached,
            nothing failed and, under -Check, nothing would change.

        .DESCRIPTION
            Everything Ansible says goes to the run folder's run.log; one
            line is written as each of the playbook's plays ends, with the
            times, as Microsoft DSC's steps have them. A run that fails is
            refused with Ansible's last words; under -Check a host not
            reached, as a machine not made yet, is answered not in its
            desired state instead. Each host -Named names that the recap
            lacks, one a play run a host at a time never came to, is
            answered unreached. -AskPass asks for the Windows machines'
            Administrator password, which no file holds.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Inventory,

        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [string] $Log,

        [Parameter()]
        [string[]] $Named = @(),

        [Parameter()]
        [switch] $Check,

        [Parameter()]
        [switch] $AskPass
    )

    if ($null -eq (Get-Command -Name 'ansible-playbook' -ErrorAction SilentlyContinue)) {
        throw ("REFUSED: ansible-playbook is not on PATH. $script:XmipPrerequisiteName's " +
            '[prerequisite.ansible] installs ansible-core into a folder of its own, ' +
            'whose bin goes on PATH.')
    }
    [string] $playbook = Join-Path $Estate 'deploy/dsc/ansible/environment.yml'
    [string[]] $arguments = @('--inventory', $Inventory, $playbook)
    if ($Check) {
        $arguments += @('--check', '--diff')
    }
    if ($AskPass) {
        $arguments += '--ask-pass'
    }
    [string] $trace = Join-Path $Log 'run.log'
    [datetime] $started = [datetime]::UtcNow
    "== $($started.ToString('o')) ansible-playbook $($arguments -join ' ')" |
        Add-Content -LiteralPath $trace
    [int] $count = @(Get-Content -LiteralPath $playbook |
            Where-Object { $_ -match '^- name:' }).Count
    [hashtable] $play = @{ Name = ''; Failed = $false; Begun = $started; Index = -1 }
    [scriptblock] $ended = {
        if ($play.Index -lt 0) {
            return
        }
        [hashtable] $result = @{
            InDesiredState = -not $play.Failed
            Seconds = [int] ([datetime]::UtcNow - $play.Begun).TotalSeconds
        }
        [hashtable] $at = @{ Index = $play.Index; Count = $count; Started = $started }
        Write-XmipDeployLine -Step @{ Name = $play.Name } -Result $result @at
    }
    [string] $color = $env:ANSIBLE_NOCOLOR
    $env:ANSIBLE_NOCOLOR = '1'
    try {
        # Each line as Ansible writes it, so a play's line comes as it ends.
        & ansible-playbook @arguments 2>&1 | ForEach-Object {
            $line = "$_"
            Add-Content -LiteralPath $trace -Value $line
            # A play run one host at a time says its name once per host: one play.
            if ($line -match '^PLAY \[(.*)\]' -and $Matches[1] -ne $play.Name) {
                & $ended
                $play.Name = $Matches[1]
                $play.Failed = $false
                $play.Begun = [datetime]::UtcNow
                $play.Index++
            }
            elseif ($line -match '^(fatal|failed):' -or ($Check -and $line -match '^changed:')) {
                # Under --check a change is what a run would make.
                $play.Failed = $true
            }
        }
        [int] $exit = $LASTEXITCODE
        & $ended
    }
    finally {
        $env:ANSIBLE_NOCOLOR = $color
    }
    [string[]] $said = @(Get-Content -LiteralPath $trace -Tail 400)
    [int] $from = [Array]::LastIndexOf($said, ($said | Where-Object { $_ -like 'PLAY RECAP*' } |
                Select-Object -Last 1))
    [string] $recap = '^(\S+)\s+:\s+ok=(\d+)\s+changed=(\d+)\s+unreachable=(\d+)\s+failed=(\d+)'
    [object[]] $hosts = @(if ($from -ge 0) {
            foreach ($line in $said[$from..($said.Count - 1)]) {
                if ($line -match $recap) {
                    [pscustomobject] @{
                        Host = $Matches[1]
                        Ok = [int] $Matches[2]
                        Changed = [int] $Matches[3]
                        Unreachable = [int] $Matches[4]
                        Failed = [int] $Matches[5]
                        # Under --check a change is what a run would make.
                        InDesiredState = $Matches[4] -eq '0' -and $Matches[5] -eq '0' -and (
                            -not $Check -or $Matches[3] -eq '0')
                    }
                }
            }
        })
    # A host the playbook never reached, as one after an unreached one in a
    # play run a host at a time, is answered unreached.
    foreach ($name in @($Named | Where-Object { $_ -notin @($hosts | ForEach-Object Host) })) {
        $hosts += [pscustomobject] @{ Host = $name; Ok = 0; Changed = 0; Unreachable = 1
            Failed = 0; InDesiredState = $false }
    }
    # A check of machines not made yet reaches none of them: that is its answer.
    [bool] $unmade = $Check -and $hosts.Count -gt 0 -and
        @($hosts | Where-Object { $_.Failed -gt 0 }).Count -eq 0
    if ($exit -ne 0 -and -not $unmade) {
        [string[]] $last = @($said | Where-Object { $_ -match '^(fatal|failed|ERROR)' } |
            Select-Object -Last 3)
        throw "REFUSED: ansible-playbook exit $exit. $($last -join ' ') ($trace)"
    }
    return $hosts
}
