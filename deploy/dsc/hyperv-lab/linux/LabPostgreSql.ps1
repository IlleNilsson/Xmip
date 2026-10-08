#requires -PSEdition Core
#requires -Version 7.6.5
# PostgreSQL on an AlmaLinux lab guest, from the PostgreSQL project's packages
# (PGDG), set up as deploy/database/postgresql/README.md tells IT to: the
# server settings Xmip depends on, TLS 1.3 only for xmip_storage, and the
# generated scripts 01 to 04 run on the primary. A standby is a streaming
# replica of its primary over a physical replication slot; the replication
# and its failover are the lab's, as IT's (deployment-model.md section 9).
# This file reads; LabPostgreSqlSetup.ps1 changes. Dot-sourced by
# LabLinuxGuest.ps1, whose Invoke-LabNative both call.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LabPostgreSqlPath {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [string] $version = [string] $Machine.PostgreSql.MajorVersion
    return @{
        Bin = "/usr/pgsql-$version/bin"
        Data = "/var/lib/pgsql/$version/data"
        Tls = "/var/lib/pgsql/$version/tls"
        Service = "postgresql-$version"
        Package = "postgresql$version-server"
    }
}

function Get-LabPostgreSqlSetting {
    <#
    .SYNOPSIS
    The server settings the lab sets on a primary, which its standbys copy.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [string] $tls = (Get-LabPostgreSqlPath -Machine $Machine).Tls
    return [ordered] @{
        listen_addresses = '*'
        port = [string] $Machine.PostgreSql.Port
        fsync = 'on'
        synchronous_commit = 'on'
        full_page_writes = 'on'
        password_encryption = 'scram-sha-256'
        ssl = 'on'
        ssl_cert_file = "$tls/server.crt"
        ssl_key_file = "$tls/server.key"
        ssl_min_protocol_version = 'TLSv1.3'
    }
}

function Get-LabPostgreSqlHba {
    <#
    .SYNOPSIS
    The whole pg_hba.conf: xmip_storage over TLS from the lab network only,
    replication from each standby, and nothing remote in the clear.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [string[]] $lines = @(
        '# Written by the Xmip Hyper-V lab; replaced on every configuration.'
        'local     all                                all               peer'
        "hostssl   xmip_runtime,xmip_administration  xmip_storage      $($Machine.NetworkPrefix)" +
            '  scram-sha-256'
    )
    foreach ($standby in @($Machine.PostgreSql.Standbys)) {
        $lines += "hostssl   replication  xmip_replication  $($standby.Address)/32  scram-sha-256"
    }
    $lines += 'hostnossl all                                all               0.0.0.0/0  reject'
    return ($lines -join "`n") + "`n"
}

function Invoke-LabPsql {
    <#
    .SYNOPSIS
    Runs SQL as the postgres superuser over the local socket; returns its rows.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [string] $Sql,

        [string] $Database = 'postgres'
    )

    [string] $psql = "$((Get-LabPostgreSqlPath -Machine $Machine).Bin)/psql"
    [string[]] $arguments = @('-u', 'postgres', '--', $psql, '-X', '-q', '-t', '-A',
        '-v', 'ON_ERROR_STOP=1', '-p', [string] $Machine.PostgreSql.Port, '-d', $Database)
    return Invoke-LabNative -FilePath runuser -ArgumentList $arguments -InputText $Sql
}

function Get-LabFirewallRule {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    return "rule family=`"ipv4`" source address=`"$($Machine.NetworkPrefix)`" " +
        "port port=`"$($Machine.PostgreSql.Port)`" protocol=`"tcp`" accept"
}

function Get-LabPostgreSqlFinding {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [hashtable] $path = Get-LabPostgreSqlPath -Machine $Machine
    if (-not (Test-Path -LiteralPath "$($path.Bin)/postgres" -PathType Leaf)) {
        return "PostgreSQL $($Machine.PostgreSql.MajorVersion) is not installed."
    }
    if ((& systemctl is-active $path.Service) -ne 'active') {
        return 'PostgreSQL is not running.'
    }
    [System.Collections.Specialized.OrderedDictionary] $settings =
        Get-LabPostgreSqlSetting -Machine $Machine
    foreach ($name in $settings.Keys) {
        [string] $actual = (Invoke-LabPsql -Machine $Machine -Sql "SHOW $name;") -join ''
        if ($actual -ne $settings[$name]) {
            Write-Output -InputObject "PostgreSQL $name is '$actual', not '$($settings[$name])'."
        }
    }
    [string] $hba = Get-Content -LiteralPath "$($path.Data)/pg_hba.conf" -Raw
    if ($hba -ne (Get-LabPostgreSqlHba -Machine $Machine)) {
        Write-Output -InputObject "pg_hba.conf differs from the lab's."
    }
    & firewall-cmd "--query-rich-rule=$(Get-LabFirewallRule -Machine $Machine)" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output -InputObject 'The firewall does not admit the lab network to PostgreSQL.'
    }
    if ($null -eq $Machine.PostgreSql.Primary) {
        Get-LabPrimaryFinding -Machine $Machine
    }
    else {
        Get-LabStandbyFinding -Machine $Machine
    }
}

function Get-LabPrimaryFinding {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [string] $sql = "SELECT rolname FROM pg_authid WHERE rolname = 'xmip_owner' " +
        "OR (rolname IN ('xmip_storage', 'xmip_replication') AND rolpassword IS NOT NULL);"
    [string[]] $roles = @(Invoke-LabPsql -Machine $Machine -Sql $sql)
    foreach ($role in @('xmip_owner', 'xmip_storage', 'xmip_replication')) {
        if ($role -notin $roles) {
            Write-Output -InputObject "Role $role is missing or has no password."
        }
    }
    foreach ($database in @('xmip_runtime', 'xmip_administration')) {
        [string] $exists = (Invoke-LabPsql -Machine $Machine -Sql (
            "SELECT 1 FROM pg_database WHERE datname = '$database';")) -join ''
        if ($exists -ne '1') {
            Write-Output -InputObject "Database $database is missing."
            continue
        }
        [string] $schema = (Invoke-LabPsql -Machine $Machine -Database $database -Sql (
            "SELECT 1 FROM pg_namespace WHERE nspname = 'xmip';")) -join ''
        if ($schema -ne '1') {
            Write-Output -InputObject "Schema xmip is missing in $database."
        }
    }
    [string[]] $slots = @(Invoke-LabPsql -Machine $Machine -Sql (
        'SELECT slot_name FROM pg_replication_slots;'))
    foreach ($standby in @($Machine.PostgreSql.Standbys)) {
        if ($standby.Slot -notin $slots) {
            Write-Output -InputObject "Replication slot $($standby.Slot) is missing."
        }
    }
}

function Get-LabStandbyFinding {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [string] $recovery = (Invoke-LabPsql -Machine $Machine -Sql (
        'SELECT pg_is_in_recovery();')) -join ''
    if ($recovery -ne 't') {
        return 'The standby is not in recovery.'
    }
    [string] $status = (Invoke-LabPsql -Machine $Machine -Sql (
        'SELECT status FROM pg_stat_wal_receiver;')) -join ''
    if ($status -ne 'streaming') {
        Write-Output -InputObject "The standby is not streaming from its primary ($status)."
    }
}
