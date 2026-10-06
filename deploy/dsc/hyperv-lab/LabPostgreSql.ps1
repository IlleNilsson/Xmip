# Invoked only inside a Windows guest through PowerShell Direct.
[CmdletBinding()]
[OutputType([void])]
param(
    [Parameter(Mandatory = $true)]
    [hashtable] $Lab,

    [Parameter(Mandatory = $true)]
    [hashtable] $Secret
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[string] $prefix = "C:\Program Files\PostgreSQL\$($Lab.PostgreSql.MajorVersion)"
[string] $data = 'C:\XmipLab\PostgreSql'
[string] $options = 'C:\ProgramData\XmipLab\postgresql.options'
if ($null -eq (Get-Service -Name XmipPostgreSql -ErrorAction SilentlyContinue)) {
    [string] $password = $Secret.PostgreSqlPassword.GetNetworkCredential().Password
    if ($password -match '[\r\n]' -or $password.Length -lt 14) {
        throw 'The PostgreSQL password must have 14+ characters and contain no newlines.'
    }
    # Parent payload directory is restricted to SYSTEM and local administrators.
    [string[]] $settings = @(
        'mode=unattended'
        'unattendedmodeui=none'
        'enable-components=server,commandlinetools'
        "prefix=$prefix"
        "datadir=$data"
        "serverport=$($Lab.PostgreSql.Port)"
        'servicename=XmipPostgreSql'
        'serviceaccount=NT AUTHORITY\NetworkService'
        'superaccount=postgres'
        "superpassword=$password"
    )
    try {
        $settings | Set-Content -LiteralPath $options -Encoding UTF8
        [hashtable] $install = @{
            FilePath = 'C:\ProgramData\XmipLab\postgresql.exe'
            ArgumentList = '--optionfile C:\ProgramData\XmipLab\postgresql.options'
            Wait = $true
            PassThru = $true
        }
        [object] $process = Start-Process @install
        if ($process.ExitCode -ne 0) {
            throw "PostgreSQL installer failed with exit code $($process.ExitCode)."
        }
    }
    finally {
        Remove-Item -LiteralPath $options -Force -ErrorAction SilentlyContinue
        $password = ''
    }
}

[string] $config = Join-Path -Path $data -ChildPath 'postgresql.conf'
[string] $hba = Join-Path -Path $data -ChildPath 'pg_hba.conf'
[string] $listener = "listen_addresses = '*'"
[string] $rule = "host all all $($Lab.Network.Prefix) scram-sha-256"
[bool] $changed = $false
if ((Get-Content -LiteralPath $config -Raw) -notmatch [regex]::Escape($listener)) {
    Add-Content -LiteralPath $config -Value $listener
    $changed = $true
}
if ((Get-Content -LiteralPath $hba -Raw) -notmatch [regex]::Escape($rule)) {
    Add-Content -LiteralPath $hba -Value $rule
    $changed = $true
}
if ($changed) {
    Restart-Service -Name XmipPostgreSql
}
else {
    Start-Service -Name XmipPostgreSql
}
[object] $firewall = Get-NetFirewallRule -Name XmipPostgreSql -ErrorAction SilentlyContinue
if ($null -eq $firewall) {
    [hashtable] $allow = @{
        Name = 'XmipPostgreSql'
        DisplayName = 'Xmip lab PostgreSQL'
        Direction = 'Inbound'
        Action = 'Allow'
        Protocol = 'TCP'
        LocalPort = $Lab.PostgreSql.Port
        RemoteAddress = $Lab.Network.Prefix
        Profile = 'Domain'
    }
    New-NetFirewallRule @allow | Out-Null
}
else {
    Set-NetFirewallRule -Name XmipPostgreSql -Enabled True
}

# No replication is implied: these are two independent PostgreSQL test servers.
if ($Lab.PostgreSql.Database -notmatch '^[a-z][a-z0-9_]*$') {
    throw 'Database must be a lowercase SQL identifier.'
}
$env:PGPASSWORD = $Secret.PostgreSqlPassword.GetNetworkCredential().Password
try {
    [string[]] $connection = @('-U', 'postgres', '-h', '127.0.0.1',
        '-p', [string] $Lab.PostgreSql.Port)
    [string] $query = "SELECT 1 FROM pg_database WHERE datname='$($Lab.PostgreSql.Database)'"
    [string] $found = & "$prefix\bin\psql.exe" @connection -d postgres -tAc $query
    if ($LASTEXITCODE -ne 0) {
        throw 'Cannot authenticate to the PostgreSQL server.'
    }
    if ($found.Trim() -ne '1') {
        & "$prefix\bin\createdb.exe" @connection $Lab.PostgreSql.Database
        if ($LASTEXITCODE -ne 0) {
            throw 'Cannot create the Xmip test database.'
        }
    }
}
finally {
    Remove-Item -LiteralPath Env:PGPASSWORD -ErrorAction SilentlyContinue
}
