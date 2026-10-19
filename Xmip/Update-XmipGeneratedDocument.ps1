#requires -PSEdition Core
#requires -Version 7.6.7

<#
.SYNOPSIS
    Regenerating the estate's generated documents at the start of a landing.

.DESCRIPTION
    The estate map and the decision index are views of the tree (ADR-0060,
    ADR-0020 clause 5), and test/ byte-compares each with what its generator
    produces. The map was regenerated when the landing pinned, after test/ had
    already run against the tree, so a landing whose sources changed a line
    count failed EstateMap.Test.ps1 and stopped; four landings did on
    2026-10-13. Regenerated before verification starts, the committed map is
    true of the tree being landed, and the pin commits it with the rest.

    Style: doc/governance/powershell-style.md
#>


function Update-XmipGeneratedDocument {
    <#
        .SYNOPSIS
            Regenerates doc/architecture/estate-map.md and doc/decision/README.md
            from the working tree, before a landing reads what changed.

        .DESCRIPTION
            Called once, by Publish-XmipChange, before it reads the estate, so
            both the landing and the -Pin repair path commit a map true of
            what they pin. A document that will not generate warns rather than
            stopping the landing: test/ then says what is wrong with it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    try {
        New-XmipEstateMap -Root $RepositoryRoot -Save | Out-Null
    }
    catch {
        Write-Warning "The estate map was not regenerated: $($_.Exception.Message)"
    }

    [string] $decision = Join-Path -Path $RepositoryRoot -ChildPath 'doc/decision'

    try {
        New-XmipDecisionIndex -DecisionRoot $decision -Save | Out-Null
    }
    catch {
        Write-Warning "The decision index was not regenerated: $($_.Exception.Message)"
    }
}
