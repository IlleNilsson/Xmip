#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The event source the operating system's log is written under when audit
    cannot persist a record (ADR-0062), for Install-XmipPrerequisite.

.DESCRIPTION
    Windows only. Registering it needs
    elevation once and this never elevates: an elevated -Install registers
    it, anything else says so and prints the line. Until it is registered
    the fallback writes under .NET Runtime and says so in the entry. The
    name is the ABI header's XMIP_EVENT_SOURCE, read where it is declared:
    the prerequisites run before anything is built, so there is no binding
    yet to ask.

    Style: doc/governance/powershell-style.md
#>


function Install-XmipEventSource {
    <#
        .SYNOPSIS
            Reports, and with -Install registers, the event source; returns
            what it found as Xmip.Prerequisite lines, nothing where the role
            or the platform has none.

        .PARAMETER Manifest
            prerequisite.toml, as Read-XmipToml read it.

        .PARAMETER ManifestPath
            Its path, beside which the ABI header declares the source's name.

        .PARAMETER Role
            The roles the run is for.

        .PARAMETER Install
            Register it, rather than say how.

        .PARAMETER Caller
            Install-XmipPrerequisite itself, for ShouldProcess.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.Prerequisite')]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [string] $ManifestPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Role,

        [Parameter(Mandatory = $false)]
        [switch] $Install,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet] $Caller
    )

    $eventSource = Get-TomlValue -Node $Manifest -Name 'eventSource' -Default $null

    if ($IsWindows -and $eventSource -and
        ($Role -contains [string](Get-TomlValue -Node $eventSource -Name 'role'))) {
        [string] $header = Join-Path -Path (Split-Path -Parent $ManifestPath) -ChildPath (
            'module/foundation/abi/include/xmip_operate.h')
        $declared = Select-String -LiteralPath $header -Pattern (
            '^#define\s+XMIP_EVENT_SOURCE\s+"([^"]+)"') | Select-Object -First 1

        if ($null -eq $declared) {
            throw "XMIP_EVENT_SOURCE is not declared in $header."
        }

        [string] $sourceName = $declared.Matches[0].Groups[1].Value
        [string] $sourceLog = [string](Get-TomlValue -Node $eventSource -Name 'log')
        [string] $label = "event source $sourceName"
        [string] $line = ("[System.Diagnostics.EventLog]::CreateEventSource(" +
            "'$sourceName', '$sourceLog')")
        [bool] $registered = $false

        # Asked unelevated about a source that is not there, EventLog searches
        # the Security log too and is refused; that is "not registered".
        try {
            $registered = [System.Diagnostics.EventLog]::SourceExists($sourceName)
        }
        catch {
            $registered = $false
        }

        $principal = [Security.Principal.WindowsPrincipal](
            [Security.Principal.WindowsIdentity]::GetCurrent())
        [bool] $elevated = $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($registered) {
            Write-Host "PRESENT: $label  ($sourceLog)"
            New-XmipPrerequisiteResult -Name $label -Status 'present' -Detail $sourceLog
        }
        elseif (-not $elevated) {
            Write-Warning "NEEDS ELEVATION: $label"
            Write-Host "    $line"
            New-XmipPrerequisiteResult -Name $label -Status 'needs-elevation' -Detail $line
        }
        elseif (-not $Install) {
            Write-Warning "MISSING: $label"
            Write-Host "    $line"
            New-XmipPrerequisiteResult -Name $label -Status 'missing' -Detail $line
        }
        elseif ($Caller.ShouldProcess($label, $line)) {
            Write-Host "INSTALL: $label"
            [System.Diagnostics.EventLog]::CreateEventSource($sourceName, $sourceLog)
            New-XmipPrerequisiteResult -Name $label -Status 'installed' -Detail $line
        }
        else {
            New-XmipPrerequisiteResult -Name $label -Status 'would-install' -Detail $line
        }
    }
}
