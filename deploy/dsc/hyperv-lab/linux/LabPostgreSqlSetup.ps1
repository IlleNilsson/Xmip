#requires -PSEdition Core
#requires -Version 7.6.5
# Setting PostgreSQL up on an AlmaLinux lab guest: what LabPostgreSql.ps1
# checks, made so. The primary runs deploy/database/postgresql's scripts and
# holds a replication slot per standby; a standby is copied from its primary
# with pg_basebackup. Dot-sourced by LabLinuxGuest.ps1 after LabPostgreSql.ps1.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-LabSqlLiteral {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    if ($Value -match '[\r\n]' -or $Value.Length -lt 14) {
        throw 'A lab database password has 14 or more characters and no line break.'
    }
    return "'" + ($Value -replace "'", "''") + "'"
}

function Install-LabPostgreSql {
    <#
    .SYNOPSIS
    The PGDG repository and server package, and the server's TLS files.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [hashtable] $path = Get-LabPostgreSqlPath -Machine $Machine
    if (-not (Test-Path -LiteralPath "$($path.Bin)/postgres" -PathType Leaf)) {
        [string] $repository = 'https://download.postgresql.org/pub/repos/yum/reporpms/' +
            'EL-10-x86_64/pgdg-redhat-repo-latest.noarch.rpm'
        Invoke-LabNative -FilePath dnf -ArgumentList @('install', '-y', $repository) | Out-Null
        Invoke-LabNative -FilePath dnf -ArgumentList @('install', '-y', $path.Package) | Out-Null
    }
    [string[]] $directory = @('-d', '-o', 'postgres', '-g', 'postgres', '-m', '0700', $path.Tls)
    Invoke-LabNative -FilePath install -ArgumentList $directory | Out-Null
    foreach ($file in @('server.crt', 'server.key', 'authority.pem')) {
        [string] $source = Join-Path -Path $PSScriptRoot -ChildPath "tls/$file"
        [string[]] $copy = @('-o', 'postgres', '-g', 'postgres', '-m', '0600', $source,
            "$($path.Tls)/$file")
        Invoke-LabNative -FilePath install -ArgumentList $copy | Out-Null
    }
}

function Write-LabPostgreSqlHba {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [string] $hba = "$((Get-LabPostgreSqlPath -Machine $Machine).Data)/pg_hba.conf"
    [IO.File]::WriteAllText($hba, (Get-LabPostgreSqlHba -Machine $Machine))
    Invoke-LabNative -FilePath chown -ArgumentList @('postgres:postgres', $hba) | Out-Null
    Invoke-LabNative -FilePath chmod -ArgumentList @('0600', $hba) | Out-Null
}

function Set-LabPostgreSql {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [hashtable] $Secret
    )

    [hashtable] $path = Get-LabPostgreSqlPath -Machine $Machine
    Install-LabPostgreSql -Machine $Machine
    if (-not (Test-Path -LiteralPath "$($path.Data)/PG_VERSION" -PathType Leaf)) {
        if ($null -eq $Machine.PostgreSql.Primary) {
            [string] $setup = "$($path.Bin)/postgresql-$($Machine.PostgreSql.MajorVersion)-setup"
            Invoke-LabNative -FilePath $setup -ArgumentList @('initdb') | Out-Null
        }
        else {
            Copy-LabStandby -Machine $Machine -Secret $Secret
        }
    }
    Write-LabPostgreSqlHba -Machine $Machine
    Invoke-LabNative -FilePath systemctl -ArgumentList @('enable', '--now', $path.Service) |
        Out-Null
    if ($null -eq $Machine.PostgreSql.Primary) {
        Set-LabPrimary -Machine $Machine -Secret $Secret
    }
    Invoke-LabNative -FilePath systemctl -ArgumentList @('reload', $path.Service) | Out-Null
    [string] $rule = "--add-rich-rule=$(Get-LabFirewallRule -Machine $Machine)"
    Invoke-LabNative -FilePath firewall-cmd -ArgumentList @('--permanent', $rule) | Out-Null
    Invoke-LabNative -FilePath firewall-cmd -ArgumentList @('--reload') | Out-Null
}

function Set-LabPrimary {
    <#
    .SYNOPSIS
    The primary's settings, the generated scripts where their work is missing,
    the two login passwords, and a replication slot per standby.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [hashtable] $Secret
    )

    [System.Collections.Specialized.OrderedDictionary] $settings =
        Get-LabPostgreSqlSetting -Machine $Machine
    [bool] $restart = $false
    foreach ($name in $settings.Keys) {
        [string] $actual = (Invoke-LabPsql -Machine $Machine -Sql "SHOW $name;") -join ''
        if ($actual -ne $settings[$name]) {
            [string] $value = "'" + ($settings[$name] -replace "'", "''") + "'"
            Invoke-LabPsql -Machine $Machine -Sql "ALTER SYSTEM SET $name = $value;" | Out-Null
            $restart = $true
        }
    }
    if ($restart) {
        [string] $service = (Get-LabPostgreSqlPath -Machine $Machine).Service
        Invoke-LabNative -FilePath systemctl -ArgumentList @('restart', $service) | Out-Null
    }
    Invoke-LabSchemaScript -Machine $Machine
    if (-not $Secret.ContainsKey('StoragePassword') -or
        -not $Secret.ContainsKey('ReplicationPassword')) {
        throw 'The lab passwords did not reach the guest; Set runs from the host only.'
    }
    [string] $storage = ConvertTo-LabSqlLiteral -Value $Secret.StoragePassword
    [string] $replication = ConvertTo-LabSqlLiteral -Value $Secret.ReplicationPassword
    [string] $missing = 'WHERE NOT EXISTS (SELECT 1 FROM pg_roles ' +
        "WHERE rolname = 'xmip_replication')"
    [string[]] $statements = @(
        "ALTER ROLE xmip_storage PASSWORD $storage;"
        "SELECT 'CREATE ROLE xmip_replication LOGIN REPLICATION' $missing \gexec"
        "ALTER ROLE xmip_replication PASSWORD $replication;"
    )
    foreach ($standby in @($Machine.PostgreSql.Standbys)) {
        [string] $slot = $standby.Slot
        $statements += "SELECT pg_create_physical_replication_slot('$slot') WHERE NOT EXISTS " +
            "(SELECT 1 FROM pg_replication_slots WHERE slot_name = '$slot');"
    }
    Invoke-LabPsql -Machine $Machine -Sql ($statements -join "`n") | Out-Null
}

function Invoke-LabSchemaScript {
    <#
    .SYNOPSIS
    Runs deploy/database/postgresql's scripts in order, each only where what
    it makes is missing, since none of them may run twice.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [string] $schema = "SELECT 1 FROM pg_namespace WHERE nspname = 'xmip';"
    [hashtable[]] $steps = @(
        @{
            Script = '01-roles.sql'
            Database = 'postgres'
            Probe = "SELECT 1 FROM pg_roles WHERE rolname = 'xmip_owner';"
        }
        @{
            Script = '02-databases.sql'
            Database = 'postgres'
            Probe = "SELECT 1 FROM pg_database WHERE datname = 'xmip_runtime';"
        }
        @{
            Script = '03-runtime.sql'
            Database = 'xmip_runtime'
            Probe = $schema
        }
        @{
            Script = '04-administration.sql'
            Database = 'xmip_administration'
            Probe = $schema
        }
    )
    foreach ($step in $steps) {
        [hashtable] $probe = @{ Machine = $Machine; Database = $step.Database; Sql = $step.Probe }
        if (((Invoke-LabPsql @probe) -join '') -eq '1') {
            continue
        }
        [string] $file = Join-Path -Path $PSScriptRoot -ChildPath "sql/$($step.Script)"
        [string] $sql = Get-Content -LiteralPath $file -Raw
        Invoke-LabPsql -Machine $Machine -Database $step.Database -Sql $sql | Out-Null
    }
}

function Copy-LabStandby {
    <#
    .SYNOPSIS
    Makes an empty standby a streaming replica: pg_basebackup from its primary
    over TLS, checked against the lab's authority by name, into its slot.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [hashtable] $Secret
    )

    [hashtable] $path = Get-LabPostgreSqlPath -Machine $Machine
    [hashtable] $primary = $Machine.PostgreSql.Primary
    [string] $port = [string] $Machine.PostgreSql.Port
    if (-not $Secret.ContainsKey('ReplicationPassword') -or
        $Secret.ReplicationPassword -match '[\r\n:\\]') {
        throw 'The replication password did not reach the guest, or cannot be kept in .pgpass.'
    }
    [string] $passfile = '/var/lib/pgsql/.pgpass'
    [string] $entry = "$($primary.Fqdn):${port}:replication:xmip_replication:" +
        $Secret.ReplicationPassword
    [IO.File]::WriteAllText($passfile, "$entry`n")
    Invoke-LabNative -FilePath chown -ArgumentList @('postgres:postgres', $passfile) | Out-Null
    Invoke-LabNative -FilePath chmod -ArgumentList @('0600', $passfile) | Out-Null
    [string] $connection = "host=$($primary.Fqdn) port=$port user=xmip_replication " +
        "sslmode=verify-full sslrootcert=$($path.Tls)/authority.pem passfile=$passfile"
    [string[]] $backup = @('-u', 'postgres', '--', "$($path.Bin)/pg_basebackup",
        '-d', $connection, '-D', $path.Data, '-R', '-X', 'stream', '-S', $primary.Slot)
    Invoke-LabNative -FilePath runuser -ArgumentList $backup | Out-Null
}
