#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    How long each module, the root crate and test/ took when a landing last
    verified them, so the next landing's first estimate is informed.

.DESCRIPTION
    Kept on this machine only, under .local-work: a duration measured here
    says nothing about another machine.

    Style: doc/governance/powershell-style.md
#>

# Where the durations are kept, relative to the repository root.
[string] $script:XmipVerifyTimeFile = '.local-work/verify-time.json'

function Get-XmipVerifyTime {
    <#
        .SYNOPSIS
            The last recorded verify duration of every module, '.' for the
            root crate and 'test/' for the root's own tests.

        .DESCRIPTION
            Returns a hashtable of name to duration; empty when nothing was
            recorded or the record cannot be read, since an estimate is never
            worth stopping a landing for.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    [hashtable] $time = @{}
    [string] $path = Join-Path -Path $RepositoryRoot -ChildPath $script:XmipVerifyTimeFile

    if (-not (Test-Path -LiteralPath $path)) {
        return $time
    }

    try {
        $read = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -AsHashtable

        foreach ($name in $read.Keys) {
            $time[$name] = [timespan]::FromSeconds([double] $read[$name])
        }
    }
    catch {
        Write-Warning "The recorded verify times were not read: $($_.Exception.Message)"
    }

    return $time
}

function Set-XmipVerifyTime {
    <#
        .SYNOPSIS
            Records how long one module, '.' or 'test/' took to verify.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [timespan] $Duration
    )

    [string] $path = Join-Path -Path $RepositoryRoot -ChildPath $script:XmipVerifyTimeFile
    [hashtable] $time = Get-XmipVerifyTime -RepositoryRoot $RepositoryRoot
    $time[$Name] = $Duration

    [hashtable] $second = @{}
    $time.Keys | ForEach-Object { $second[$_] = [math]::Round($time[$_].TotalSeconds, 1) }

    if ($PSCmdlet.ShouldProcess($path, "Record $Name's verify time")) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        $second | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8
    }
}
