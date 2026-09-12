#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Stop-XmipWeb {
    <#
        .SYNOPSIS
            Stops Xmip web monitors — the ones given, or every one on the
            machine.

        .PARAMETER Web
            The hosts to stop, from Get-XmipWeb.

        .PARAMETER Id
            The process ids of the hosts to stop.

        .EXAMPLE
            Stop-XmipWeb

        .EXAMPLE
            Get-XmipWeb | Where-Object -Property Url -Like -Value '*5087' | Stop-XmipWeb
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Medium',
        DefaultParameterSetName = 'All')]
    [OutputType([void])]
    param(
        [Parameter(ParameterSetName = 'Object', ValueFromPipeline)]
        [PSTypeName('Xmip.Web')]
        [PSObject[]] $Web,

        [Parameter(ParameterSetName = 'Id', Mandatory)]
        [int[]] $Id
    )

    begin {
        $ErrorActionPreference = 'Stop'
        [System.Collections.Generic.List[int]] $targets = @()
    }

    process {
        foreach ($item in @($Web)) {
            if ($null -ne $item) {
                $targets.Add([int] $item.Id)
            }
        }

        if ($PSBoundParameters.ContainsKey('Id')) {
            $targets.AddRange($Id)
        }
    }

    end {
        [object[]] $running = @(Get-XmipWeb)

        if ($PSCmdlet.ParameterSetName -eq 'All') {
            $targets.AddRange([int[]] @($running | ForEach-Object { $_.Id }))
        }

        foreach ($number in @($targets | Sort-Object -Unique)) {
            $found = $running | Where-Object { $_.Id -eq $number } | Select-Object -First 1

            if ($null -eq $found) {
                Write-Error "No Xmip web monitor has pid $number. Get-XmipWeb lists them."
                continue
            }

            if ($PSCmdlet.ShouldProcess("web monitor at $($found.Url) (pid $number)", 'Stop')) {
                Stop-Process -Id $number -Force -ErrorAction SilentlyContinue
                Write-Verbose "stopped web monitor $number"
            }
        }
    }
}
