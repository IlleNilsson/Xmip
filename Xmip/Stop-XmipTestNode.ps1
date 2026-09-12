#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Stop-XmipTestNode {
    <#
        .SYNOPSIS
            Stops emulated nodes: asks first through the fleet's stop file,
            ends what stays after five seconds. Every node on the machine when
            none is named.

        .DESCRIPTION
            A node checks for `stop` in its shared directory between rounds
            and exits on its own when it appears — the orderly end, which lets
            it finish the round it is in. Nodes that have not left after five
            seconds are ended. The stop file is removed afterwards so the next
            Start-XmipTestNode over the same directory is not stopped at
            once. Takes Xmip.TestNode objects from Get-XmipTestNode
            on the pipeline, or -Name, or nothing for all.

        .PARAMETER Node
            The nodes to stop, from Get-XmipTestNode.

        .PARAMETER Name
            The names of the nodes to stop, wildcards allowed.

        .EXAMPLE
            Stop-XmipTestNode

        .EXAMPLE
            Get-XmipTestNode | Where-Object Online | Stop-XmipTestNode -WhatIf
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Medium',
        DefaultParameterSetName = 'All')]
    [OutputType([void])]
    param(
        [Parameter(ParameterSetName = 'Object', ValueFromPipeline)]
        [PSTypeName('Xmip.TestNode')]
        [PSObject[]] $Node,

        [Parameter(ParameterSetName = 'Name', Mandatory)]
        [SupportsWildcards()]
        [string[]] $Name
    )

    begin {
        [System.Collections.Generic.List[PSObject]] $targets = @()
    }

    process {
        foreach ($item in @($Node)) {
            if ($null -ne $item) {
                $targets.Add($item)
            }
        }
    }

    end {
        if ($PSCmdlet.ParameterSetName -ne 'Object') {
            [bool] $named = $PSCmdlet.ParameterSetName -eq 'Name'
            [string[]] $patterns = if ($named) { $Name } else { @('*') }

            foreach ($pattern in $patterns) {
                $targets.AddRange([PSObject[]] @(Get-XmipTestNode -Name $pattern))
            }
        }

        [PSObject[]] $chosen = @(
            $targets |
                Where-Object { $PSCmdlet.ShouldProcess("node $($_.Name) (pid $($_.Id))", 'Stop') }
        )

        if ($chosen.Count -eq 0) {
            return
        }

        [string[]] $stops = @(
            $chosen |
                ForEach-Object { $_.Shared } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Where-Object { Test-Path -LiteralPath $_ } |
                Sort-Object -Unique |
                ForEach-Object { Join-Path -Path $_ -ChildPath 'stop' }
        )

        foreach ($stop in $stops) {
            New-Item -ItemType File -Path $stop -Force | Out-Null
        }

        [int[]] $ids = @($chosen | ForEach-Object { $_.Id })
        Wait-Process -Id $ids -Timeout 5 -ErrorAction SilentlyContinue
        Stop-Process -Id $ids -Force -ErrorAction SilentlyContinue

        foreach ($stop in $stops) {
            Remove-Item -LiteralPath $stop -Force -ErrorAction Ignore
        }

        Write-Verbose "stopped $($chosen.Count) node(s)"
    }
}
