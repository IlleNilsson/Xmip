#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Stop-XmipTest {
    <#
        .SYNOPSIS
            Stops Xmip test runs: the nodes each one spawned first, then the
            run, then its run record. Every run on the machine when none is
            named.

        .DESCRIPTION
            A Playground roll ended by a signal does not get to stop its own fleet, so
            this does what the roll would have: asks every node beneath it to
            leave through the fleet's stop file, waits five seconds, ends what
            stayed, then ends the roll. Takes Xmip.TestStatus objects from
            Get-XmipTest -View Status on the pipeline, or -Id, or nothing for all.

        .PARAMETER Test
            The runs to stop, from Get-XmipTestStatus.

        .PARAMETER Id
            The process ids of the runs to stop.

        .EXAMPLE
            Stop-XmipTest

        .EXAMPLE
            Get-XmipTest -View Status | Where-Object -Property Stress -EQ -Value brutal |
                Stop-XmipTest -WhatIf
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Medium',
        DefaultParameterSetName = 'All')]
    [OutputType([void])]
    param(
        [Parameter()]
        [ValidateSet('Suite', 'Node', 'Monitor')]
        [string] $Target = 'Suite',

        [Parameter(ParameterSetName = 'Object', ValueFromPipeline)]
        [PSTypeName('Xmip.TestStatus')]
        [PSObject[]] $Test,

        [Parameter(ParameterSetName = 'Id', Mandatory)]
        [int[]] $Id,

        [Parameter()]
        [SupportsWildcards()]
        [string[]] $Name = @('*')
    )

    begin {
        $ErrorActionPreference = 'Stop'
        [System.Collections.Generic.List[int]] $targets = @()
    }

    process {
        foreach ($item in @($Test)) {
            if ($null -ne $item) {
                $targets.Add([int] $item.Id)
            }
        }

        if ($PSBoundParameters.ContainsKey('Id')) {
            $targets.AddRange($Id)
        }
    }

    end {
        if ($Target -eq 'Monitor') {
            if ($PSBoundParameters.ContainsKey('Id')) {
                return Stop-XmipWeb -Id $Id -WhatIf:$WhatIfPreference
            }

            return Stop-XmipWeb -WhatIf:$WhatIfPreference
        }

        if ($Target -eq 'Node') {
            [bool] $byId = $PSBoundParameters.ContainsKey('Id')
            [PSObject[]] $nodes = @(
                Get-XmipTestNode | Where-Object {
                    $candidate = $_
                    [bool] $named = @(
                        $Name | Where-Object { $candidate.Name -like $_ }
                    ).Count -gt 0

                    if ($byId) { return $candidate.Id -in $Id }
                    return $named
                }
            )

            return Stop-XmipTestNode -Node $nodes -WhatIf:$WhatIfPreference
        }

        [object[]] $running = @(Get-XmipTestStatus)

        if ($PSCmdlet.ParameterSetName -eq 'All') {
            $targets.AddRange([int[]] @($running | ForEach-Object { $_.Id }))
        }

        foreach ($number in @($targets | Sort-Object -Unique)) {
            $roll = $running | Where-Object { $_.Id -eq $number } | Select-Object -First 1

            if ($null -eq $roll) {
                Write-Error "No Playground roll has pid $number. Get-XmipTestStatus lists them."
                continue
            }

            if (-not $PSCmdlet.ShouldProcess("roll $number ($($roll.Stress))", 'Stop')) {
                continue
            }

            Get-XmipTestNode | Where-Object { $_.Parent -eq $number } |
                Stop-XmipTestNode -Confirm:$false

            Stop-Process -Id $number -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $number -Timeout 5 -ErrorAction SilentlyContinue

            if (-not [string]::IsNullOrWhiteSpace($roll.Path)) {
                [string] $record = Join-Path -Path $roll.Path -ChildPath "roll-$number.toml"
                Remove-Item -LiteralPath $record -Force -ErrorAction SilentlyContinue
            }

            Write-Verbose "stopped roll $number"
        }
    }
}
