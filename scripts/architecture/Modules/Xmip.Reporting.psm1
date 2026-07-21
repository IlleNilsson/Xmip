Set-StrictMode -Version Latest

function New-XmipTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Mode,
        [Parameter(Mandatory)][string] $ManifestPath,
        [Parameter(Mandatory)][string] $Owner
    )

    [pscustomobject]@{
        startedAtUtc = [DateTime]::UtcNow
        finishedAtUtc = $null
        mode = $Mode
        manifestPath = $ManifestPath
        owner = $Owner
        repositories = [ordered]@{ created=0; updated=0; skipped=0; missing=0; unexpected=0; deprecated=0; retired=0; misconfigured=0 }
        submodules = [ordered]@{ added=0; present=0; missing=0; unexpected=0; incorrectUrl=0; incorrectRevision=0 }
        cargo = [ordered]@{ updated=0; current=0; missingMembers=0; unexpectedMembers=0 }
        metadata = [ordered]@{ generated=0; current=0; missing=0 }
        warnings = [Collections.Generic.List[string]]::new()
        actions = [Collections.Generic.List[object]]::new()
    }
}

function Add-XmipTransactionAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Transaction,
        [Parameter(Mandatory)][string] $Area,
        [Parameter(Mandatory)][string] $Action,
        [Parameter(Mandatory)][string] $Target,
        [string] $Detail = ''
    )

    $Transaction.actions.Add([pscustomobject]@{
        area = $Area
        action = $Action
        target = $Target
        detail = $Detail
    })
}

function Complete-XmipTransaction {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Transaction)
    $Transaction.finishedAtUtc = [DateTime]::UtcNow
    $Transaction
}

function Show-XmipTransaction {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Transaction)

    Write-Host ''
    Write-Host 'Repositories' -ForegroundColor Cyan
    Write-Host '------------'
    foreach ($name in $Transaction.repositories.Keys) { Write-Host ('{0,-18}{1,6}' -f $name, $Transaction.repositories[$name]) }

    Write-Host ''
    Write-Host 'Submodules' -ForegroundColor Cyan
    Write-Host '----------'
    foreach ($name in $Transaction.submodules.Keys) { Write-Host ('{0,-18}{1,6}' -f $name, $Transaction.submodules[$name]) }

    Write-Host ''
    Write-Host 'Cargo' -ForegroundColor Cyan
    Write-Host '-----'
    foreach ($name in $Transaction.cargo.Keys) { Write-Host ('{0,-18}{1,6}' -f $name, $Transaction.cargo[$name]) }

    Write-Host ''
    Write-Host 'Metadata' -ForegroundColor Cyan
    Write-Host '--------'
    foreach ($name in $Transaction.metadata.Keys) { Write-Host ('{0,-18}{1,6}' -f $name, $Transaction.metadata[$name]) }

    if ($Transaction.warnings.Count -gt 0) {
        Write-Host ''
        Write-Host 'Warnings' -ForegroundColor Yellow
        Write-Host '--------'
        foreach ($warning in $Transaction.warnings) { Write-Warning $warning }
    }
}

function Export-XmipTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Transaction,
        [Parameter(Mandatory)][string] $Path
    )

    $directory = Split-Path -Parent $Path
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $Transaction | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

Export-ModuleMember -Function New-XmipTransaction,Add-XmipTransactionAction,Complete-XmipTransaction,Show-XmipTransaction,Export-XmipTransaction
