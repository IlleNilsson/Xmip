param(
    [Parameter(Mandatory = $true)]
    [string] $Owner
)

$Modules = @(
    @{ Path = 'file'; Repository = 'xmip-handler-file' },
    @{ Path = 'ftp'; Repository = 'xmip-handler-ftp' },
    @{ Path = 'http'; Repository = 'xmip-handler-http' },
    @{ Path = 'grpc'; Repository = 'xmip-handler-grpc' },
    @{ Path = 'soap'; Repository = 'xmip-handler-soap' },
    @{ Path = 'web-api'; Repository = 'xmip-handler-web-api' },
    @{ Path = 'websocket'; Repository = 'xmip-handler-websocket' },
    @{ Path = 'tcp-base'; Repository = 'xmip-handler-tcp-base' },
    @{ Path = 'udp-base'; Repository = 'xmip-handler-udp-base' }
)

foreach ($Module in $Modules) {
    $Url = "https://github.com/$Owner/$($Module.Repository).git"
    if (-not (Test-Path $Module.Path)) {
        git submodule add $Url $Module.Path
    }
}

git submodule update --init --recursive
