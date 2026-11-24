#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What a test computer answered over ssh, read: its refusal in its own
    words, or the objects its cmdlet answered.

.DESCRIPTION
    Invoke-XmipTestComputerShell returns what the computer wrote, every
    control character taken out; this reads it.

    Style: doc/governance/powershell-style.md
#>

function Assert-XmipTestComputerAnswer {
    <#
        .SYNOPSIS
            Refuses, in the computer's own words, an answer whose exit code
            is not zero.

        .PARAMETER Doing
            What was asked, for the words.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Computer,

        [Parameter(Mandatory)]
        [pscustomobject] $Answer,

        [Parameter(Mandatory)]
        [string] $Doing
    )

    if ($Answer.Code -eq 0) {
        return
    }

    [string] $said = (@($Answer.Err) + @($Answer.Out | Select-Object -Last 3)) -join ' '

    if ($said -match '^\s*REFUSED') {
        throw $said.Trim()
    }

    throw "FAILED. $($Computer.Name) could not $Doing (exit $($Answer.Code)): $said"
}


function Read-XmipTestComputerAnswer {
    <#
        .SYNOPSIS
            What a cmdlet answered on the computer, as objects, from the one
            line among what it wrote that carries its answer; a failure
            refused in the computer's words.

        .PARAMETER Doing
            The cmdlet, for the words of a failure.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Computer,

        [Parameter(Mandatory)]
        [pscustomobject] $Answer,

        [Parameter(Mandatory)]
        [string] $Doing
    )

    [string] $sent = ''

    foreach ($line in @($Answer.Out)) {
        if ($line.StartsWith($script:XmipTestComputerAnswer, [StringComparison]::Ordinal)) {
            $sent = $line.Substring($script:XmipTestComputerAnswer.Length)
        }
    }

    Assert-XmipTestComputerAnswer -Computer $Computer -Answer $Answer -Doing "run $Doing"

    if ($sent -eq '') {
        return
    }

    [string] $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($sent))

    return [System.Management.Automation.PSSerializer]::Deserialize($text)
}
