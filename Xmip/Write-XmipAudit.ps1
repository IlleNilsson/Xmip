#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Initialize-XmipAudit {
    <#
        .SYNOPSIS
            Points this session's audit at the estate's area, .local-work/audit,
            unless XMIP_AUDIT_DIRECTORY already names one. Private.

        .DESCRIPTION
            The variable is the audit capability's (ADR-0062); setting it here,
            before anything is started, is what makes every process the
            tooling starts — the web monitor, a roll, its cluster and nodes,
            the estate's Pester run — audit into the same file as the tooling
            itself. Called by Write-XmipAudit and by every command that
            starts a process before it starts it.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if ([string]::IsNullOrWhiteSpace($env:XMIP_AUDIT_DIRECTORY)) {
        $env:XMIP_AUDIT_DIRECTORY = Join-Path -Path (Get-XmipRepositoryRoot) -ChildPath (
            '.local-work/audit')
    }
}

function Write-XmipAudit {
    <#
        .SYNOPSIS
            Records one act of the estate's own tooling through the audit
            capability. Private to the module.

        .DESCRIPTION
            Every Xmip program audits through xmip-core-audit (ADR-0062), the
            estate's landing and test tooling among them. The record, its
            policy, its sink and the fallback to the operating system's log
            are the capability's; this module reaches it the way it reaches
            every rule it would otherwise write again — through the operator
            module, whose Xmip.Surface ProgramAudit calls the runtime's
            library (Import-XmipOperatorModule). It writes no record itself.

            The records go to the estate's area, .local-work/audit, unless
            XMIP_AUDIT_DIRECTORY says otherwise: the variable is set for this
            session when it is not, so every process the tooling starts — the
            web monitor, a roll, its cluster and its nodes — audits into the
            same file.

            It never fails the command it records. When even the operator
            module cannot be loaded, it says so as a warning, because nothing
            of Xmip fails silently and the operating system's log is the
            capability's to write.

        .PARAMETER Action
            What was done: the command's name, or what inside it failed.

        .PARAMETER Phase
            Begin, Execute, Finished or Failure.

        .PARAMETER Severity
            Information, Warning or Error. A Failure, or an Error at any
            phase, is always recorded.

        .PARAMETER Message
            What the command says about it.

        .PARAMETER Property
            What else the record carries, name to value.

        .PARAMETER ErrorRecord
            The failure itself: recorded as a Failure with its exception.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Act')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Action,

        [Parameter(ParameterSetName = 'Act')]
        [ValidateSet('Begin', 'Execute', 'Finished', 'Failure')]
        [string] $Phase = 'Execute',

        [Parameter(ParameterSetName = 'Act')]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string] $Severity = 'Information',

        [Parameter(ParameterSetName = 'Act')]
        [string] $Message,

        [Parameter()]
        [System.Collections.IDictionary] $Property = @{},

        [Parameter(Mandatory, ParameterSetName = 'Failure')]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    # Under -WhatIf nothing was done, so nothing is recorded but a failure.
    if ($WhatIfPreference -and $PSCmdlet.ParameterSetName -ne 'Failure') {
        return
    }

    try {
        Initialize-XmipAudit
        Import-XmipOperatorModule
    }
    catch {
        Write-Warning ("Xmip audit could not be reached, so '$Action' is not recorded: " +
            $_.Exception.Message)
        return
    }

    $said = [System.Collections.Generic.Dictionary[string, string]]::new()

    # A value is said as text: a list joined, a table as its pairs.
    foreach ($key in $Property.Keys) {
        $value = $Property[$key]
        $said[[string] $key] = if ($value -is [System.Collections.IDictionary]) {
            @($value.Keys | ForEach-Object { "$_=$($value[$_])" }) -join ', '
        }
        elseif ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
            @($value) -join ', '
        }
        else {
            [string] $value
        }
    }

    $audit = [Xmip.Surface.ProgramAudit]::new('Xmip', $null)


    if ($PSCmdlet.ParameterSetName -eq 'Failure') {
        if ($null -ne $ErrorRecord.InvocationInfo) {
            $said['where'] = [string] $ErrorRecord.InvocationInfo.PositionMessage
        }

        $null = $audit.Failed($Action, $ErrorRecord.Exception, $said)
        return
    }

    # The phase and severity cross as their names: PowerShell converts them to
    # the binding's enums at the call, which a type literal here could not
    # name before the binding's assembly is loaded.
    $null = $audit.Record($Action, $Phase, $Severity, $Message, $said)
}
