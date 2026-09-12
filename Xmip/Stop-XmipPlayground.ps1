#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Stop-XmipPlayground {
    <#
        .SYNOPSIS
            Stops Playground rolls: the nodes each one spawned first, then the
            roll, then its run record. Every roll on the machine when none is
            named.

        .DESCRIPTION
            A roll ended by a signal does not get to stop its own fleet, so
            this does what the roll would have: asks every node beneath it to
            leave through the fleet's stop file, waits five seconds, ends what
            stayed, then ends the roll. Takes Xmip.Playground objects from
            Get-XmipPlayground on the pipeline, or -Id, or nothing for all.

        .PARAMETER Playground
            The rolls to stop, from Get-XmipPlayground.

        .PARAMETER Id
            The process ids of the rolls to stop.

        .EXAMPLE
            Stop-XmipPlayground

        .EXAMPLE
            Get-XmipPlayground | Where-Object Stress -eq brutal | Stop-XmipPlayground -WhatIf
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Medium',
        DefaultParameterSetName = 'All')]
    [OutputType([void])]
    param(
        [Parameter(ParameterSetName = 'Object', ValueFromPipeline)]
        [PSTypeName('Xmip.Playground')]
        [PSObject[]] $Playground,

        [Parameter(ParameterSetName = 'Id', Mandatory)]
        [int[]] $Id
    )

    begin {
        [System.Collections.Generic.List[int]] $targets = @()
    }

    process {
        foreach ($item in @($Playground)) {
            if ($null -ne $item) {
                $targets.Add([int] $item.Id)
            }
        }

        if ($PSBoundParameters.ContainsKey('Id')) {
            $targets.AddRange($Id)
        }
    }

    end {
        [object[]] $running = @(Get-XmipPlayground)

        if ($PSCmdlet.ParameterSetName -eq 'All') {
            $targets.AddRange([int[]] @($running | ForEach-Object { $_.Id }))
        }

        foreach ($number in @($targets | Sort-Object -Unique)) {
            $roll = $running | Where-Object { $_.Id -eq $number } | Select-Object -First 1

            if ($null -eq $roll) {
                Write-Error "No Playground roll has pid $number. Get-XmipPlayground lists them."
                continue
            }

            if (-not $PSCmdlet.ShouldProcess("roll $number ($($roll.Stress))", 'Stop')) {
                continue
            }

            Get-XmipPlaygroundNode | Where-Object { $_.Parent -eq $number } |
                Stop-XmipPlaygroundNode -Confirm:$false

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
