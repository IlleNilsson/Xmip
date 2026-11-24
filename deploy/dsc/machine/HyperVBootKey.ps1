# The key a Windows ISO's boot prompt is answered with on a Hyper-V host,
# pressed in the VM's console. One home for both technologies (ADR-0015,
# amendment 2026-11-24): Microsoft DSC's Xmip.HyperV resources dot-source it
# (deploy/dsc/msdsc/hyperv/HyperVResource.ps1), and Ansible's xmip_machine
# role hands it to the host whole as win_powershell's script
# (tasks/hyperv-machine.yml), so it runs under Windows PowerShell there and
# asks for no PowerShell 7.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Send-HyperVBootKey {
    <#
    .SYNOPSIS
    Presses Enter in a starting VM's console for its first twenty seconds,
    forty times, half a second apart.
    .DESCRIPTION
    A Windows ISO boots only after "Press any key to boot from CD or DVD",
    and on Hyper-V nobody is there to press one. The empty disk comes first
    in the boot order, so the firmware moves on to the ISO, whose prompt
    waits about five seconds; Enter answers it. A press that comes after
    the prompt reaches the Windows Boot Manager and stops its countdown, and
    the menu then waits for a choice: Enter makes it, Windows Setup, where
    Space left a machine waiting at the menu for good (seen 2026-11-23). Once
    Windows is on the disk, the disk boots and the prompt is never shown
    again.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    [hashtable] $query = @{
        Namespace = 'root/virtualization/v2'
        ClassName = 'Msvm_ComputerSystem'
        Filter = "ElementName = '$Name'"
    }
    [object] $system = Get-CimInstance @query
    [object] $keyboard = Get-CimAssociatedInstance -InputObject $system -ResultClassName (
        'Msvm_Keyboard')
    [hashtable] $press = @{
        InputObject = $keyboard
        MethodName = 'TypeKey'
        Arguments = @{ keyCode = [uint32] 0x0D }
    }
    for ([int] $pressed = 0; $pressed -lt 40; $pressed++) {
        Invoke-CimMethod @press | Out-Null
        Start-Sleep -Milliseconds 500
    }
}
