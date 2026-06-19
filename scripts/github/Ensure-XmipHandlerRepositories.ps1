# Creates missing Xmip handler repositories using GitHub REST API.
# Requires a GitHub token with repository creation permission.

param(
    [Parameter(Mandatory = $true)]
    [string] $Owner,

    [Parameter(Mandatory = $true)]
    [securestring] $Token,

    [switch] $Private
)

$PlainToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
)

$Headers = @{
    Authorization = "token $PlainToken"
    Accept        = "application/vnd.github.v3+json"
    "User-Agent"  = "Xmip-Repository-Bootstrap"
}

$Repositories = @(
    'xmip-handler-file',
    'xmip-handler-raw-tcp',
    'xmip-handler-raw-udp',
    'xmip-handler-mllp',
    'xmip-handler-as2',
    'xmip-handler-as4',
    'xmip-handler-oftp2',
    'xmip-handler-x12',
    'xmip-handler-edifact',
    'xmip-handler-peppol',
    'xmip-handler-ubl',
    'xmip-handler-rosettanet',
    'xmip-handler-dicom',
    'xmip-handler-amqp',
    'xmip-handler-stomp',
    'xmip-handler-azure-event-hubs',
    'xmip-handler-aws-sns',
    'xmip-handler-google-pubsub',
    'xmip-handler-coap',
    'xmip-handler-mqtt-sn',
    'xmip-handler-profinet',
    'xmip-handler-ethernet-ip',
    'xmip-handler-bacnet',
    'xmip-handler-dnp3',
    'xmip-handler-iec-60870-5-104',
    'xmip-handler-iec-61850',
    'xmip-handler-knx',
    'xmip-handler-lorawan',
    'xmip-handler-zigbee',
    'xmip-handler-ble',
    'xmip-handler-ocpp',
    'xmip-handler-db-common',
    'xmip-handler-postgresql',
    'xmip-handler-mysql',
    'xmip-handler-mssql',
    'xmip-handler-oracle-db',
    'xmip-handler-db2',
    'xmip-handler-sqlite',
    'xmip-handler-mongodb',
    'xmip-handler-cassandra',
    'xmip-handler-elasticsearch',
    'xmip-handler-s3',
    'xmip-handler-azure-blob',
    'xmip-handler-google-cloud-storage',
    'xmip-handler-smtp',
    'xmip-handler-imap',
    'xmip-handler-pop3',
    'xmip-handler-microsoft-graph',
    'xmip-handler-sharepoint',
    'xmip-handler-sap',
    'xmip-handler-salesforce',
    'xmip-handler-dynamics',
    'xmip-handler-servicenow',
    'xmip-handler-oauth2',
    'xmip-handler-oidc',
    'xmip-handler-saml',
    'xmip-handler-ldap',
    'xmip-handler-kerberos',
    'xmip-handler-swift',
    'xmip-handler-iso-20022',
    'xmip-handler-fix',
    'xmip-handler-x-road',
    'xmip-handler-ogc-api',
    'xmip-handler-wms',
    'xmip-handler-wfs'
)

foreach ($Repository in $Repositories) {
    $Uri = "https://api.github.com/repos/$Owner/$Repository"

    try {
        Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers | Out-Null
        Write-Host "Exists: $Owner/$Repository"
        continue
    }
    catch {
        Write-Host "Creating: $Owner/$Repository"
    }

    $Body = @{
        name        = $Repository
        private     = [bool] $Private
        auto_init   = $true
        description = "Xmip handler repository"
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Method Post `
        -Uri "https://api.github.com/user/repos" `
        -Headers $Headers `
        -Body $Body `
        -ContentType "application/json" | Out-Null
}
