param(
    [Parameter(Mandatory = $true)]
    [string] $Owner,

    [switch] $Private
)

$Visibility = if ($Private) { '--private' } else { '--public' }

$Repositories = @(
    'xmip-handlers-common',
    'xmip-handlers-messaging',
    'xmip-handlers-device',
    'xmip-handlers-industrial',
    'xmip-handlers-marine',
    'xmip-handlers-healthcare',
    'xmip-handlers-business',
    'xmip-handlers-desktop',
    'xmip-runtimes',
    'xmip-platforms'
)

foreach ($Repository in $Repositories) {
    $FullName = "$Owner/$Repository"
    Write-Host "Ensuring repository exists: $FullName"

    gh repo view $FullName *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  exists"
        continue
    }

    gh repo create $FullName $Visibility --description "Xmip module family repository: $Repository" --add-readme
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create $FullName"
    }
}
