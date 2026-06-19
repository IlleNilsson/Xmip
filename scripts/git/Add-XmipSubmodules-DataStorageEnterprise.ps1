param([Parameter(Mandatory = $true)][string] $Owner)

$Submodules = @(
    @{ Path = 'handlers/database/common'; Repository = 'xmip-handler-db-common' },
    @{ Path = 'handlers/database/postgresql'; Repository = 'xmip-handler-postgresql' },
    @{ Path = 'handlers/database/mysql'; Repository = 'xmip-handler-mysql' },
    @{ Path = 'handlers/database/mssql'; Repository = 'xmip-handler-mssql' },
    @{ Path = 'handlers/database/oracle-db'; Repository = 'xmip-handler-oracle-db' },
    @{ Path = 'handlers/database/db2'; Repository = 'xmip-handler-db2' },
    @{ Path = 'handlers/database/sqlite'; Repository = 'xmip-handler-sqlite' },
    @{ Path = 'handlers/database/mongodb'; Repository = 'xmip-handler-mongodb' },
    @{ Path = 'handlers/database/cassandra'; Repository = 'xmip-handler-cassandra' },
    @{ Path = 'handlers/database/elasticsearch'; Repository = 'xmip-handler-elasticsearch' },
    @{ Path = 'handlers/storage/s3'; Repository = 'xmip-handler-s3' },
    @{ Path = 'handlers/storage/azure-blob'; Repository = 'xmip-handler-azure-blob' },
    @{ Path = 'handlers/storage/google-cloud-storage'; Repository = 'xmip-handler-google-cloud-storage' },
    @{ Path = 'handlers/email/smtp'; Repository = 'xmip-handler-smtp' },
    @{ Path = 'handlers/email/imap'; Repository = 'xmip-handler-imap' },
    @{ Path = 'handlers/email/pop3'; Repository = 'xmip-handler-pop3' },
    @{ Path = 'handlers/collaboration/microsoft-graph'; Repository = 'xmip-handler-microsoft-graph' },
    @{ Path = 'handlers/collaboration/sharepoint'; Repository = 'xmip-handler-sharepoint' },
    @{ Path = 'handlers/enterprise/sap'; Repository = 'xmip-handler-sap' },
    @{ Path = 'handlers/enterprise/salesforce'; Repository = 'xmip-handler-salesforce' },
    @{ Path = 'handlers/enterprise/dynamics'; Repository = 'xmip-handler-dynamics' },
    @{ Path = 'handlers/enterprise/servicenow'; Repository = 'xmip-handler-servicenow' },
    @{ Path = 'handlers/identity/oauth2'; Repository = 'xmip-handler-oauth2' },
    @{ Path = 'handlers/identity/oidc'; Repository = 'xmip-handler-oidc' },
    @{ Path = 'handlers/identity/saml'; Repository = 'xmip-handler-saml' },
    @{ Path = 'handlers/identity/ldap'; Repository = 'xmip-handler-ldap' },
    @{ Path = 'handlers/identity/kerberos'; Repository = 'xmip-handler-kerberos' },
    @{ Path = 'handlers/finance/swift'; Repository = 'xmip-handler-swift' },
    @{ Path = 'handlers/finance/iso-20022'; Repository = 'xmip-handler-iso-20022' },
    @{ Path = 'handlers/finance/fix'; Repository = 'xmip-handler-fix' },
    @{ Path = 'handlers/government/x-road'; Repository = 'xmip-handler-x-road' },
    @{ Path = 'handlers/geospatial/ogc-api'; Repository = 'xmip-handler-ogc-api' },
    @{ Path = 'handlers/geospatial/wms'; Repository = 'xmip-handler-wms' },
    @{ Path = 'handlers/geospatial/wfs'; Repository = 'xmip-handler-wfs' }
)

foreach ($Submodule in $Submodules) {
    $Url = "https://github.com/$Owner/$($Submodule.Repository).git"
    if (-not (Test-Path $Submodule.Path)) {
        git submodule add $Url $Submodule.Path
    }
}
