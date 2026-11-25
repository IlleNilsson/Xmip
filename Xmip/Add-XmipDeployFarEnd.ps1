#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Add-XmipDeployFarEnd {
    <#
        .SYNOPSIS
            The System Tests' far ends an environment runs, each on a virtual
            machine of its own, added to what Get-XmipDeployEnvironment read:
            each far end with its machine; the program each family runs them
            by; and the folder of their certificates.

        .DESCRIPTION
            The far ends are the cluster file's [environment.far_ends],
            senders and receivers (ADR-0028, amendments 2026-11-22 and
            2026-11-25). The program is xmip-system-test-external built for
            each family, which msdsc places and registers on each far end's
            machine (far-end.dsc.yaml); each far end's certificate is the
            identity folder's of its name, issued from the cluster's
            authority (Initialize-XmipDeployIdentity).

        .PARAMETER Read
            What Get-XmipDeployEnvironment read: FarEnds, Programs and
            Identity are added to it.

        .PARAMETER Facts
            What the host gives, Get-XmipDeployHost's: Programs and Identity.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter(Mandatory)]
        [hashtable] $Facts
    )

    $Read['FarEnds'] = @($Read.Listed | Where-Object { $_.kind -eq 'far end' } |
            ForEach-Object {
                @{ name = $_.name; machine = @{ name = $_.machine; address = $_.address
                        family = $_.family } }
            })
    $Read['Programs'] = if ($Read.FarEnds.Count -gt 0) { $Facts.Programs } else { @{} }
    $Read['Identity'] = if ($Read.FarEnds.Count -gt 0) { $Facts.Identity } else { '' }
}
