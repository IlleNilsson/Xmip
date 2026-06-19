param([Parameter(Mandatory = $true)][string] $Owner)

$Submodules = @(
    @{ Path = 'handlers/file'; Repository = 'xmip-handler-file' },
    @{ Path = 'handlers/file-transfer/ftp'; Repository = 'xmip-handler-ftp' },
    @{ Path = 'handlers/ip/tcp/base'; Repository = 'xmip-handler-tcp-base' },
    @{ Path = 'handlers/ip/tcp/raw-tcp'; Repository = 'xmip-handler-raw-tcp' },
    @{ Path = 'handlers/ip/udp/base'; Repository = 'xmip-handler-udp-base' },
    @{ Path = 'handlers/ip/udp/raw-udp'; Repository = 'xmip-handler-raw-udp' },
    @{ Path = 'handlers/ip/tcp/http'; Repository = 'xmip-handler-http' },
    @{ Path = 'handlers/ip/tcp/http/web-api'; Repository = 'xmip-handler-web-api' },
    @{ Path = 'handlers/ip/tcp/http/soap'; Repository = 'xmip-handler-soap' },
    @{ Path = 'handlers/ip/tcp/http/websocket'; Repository = 'xmip-handler-websocket' },
    @{ Path = 'handlers/ip/tcp/grpc'; Repository = 'xmip-handler-grpc' },
    @{ Path = 'handlers/ip/tcp/mllp'; Repository = 'xmip-handler-mllp' },
    @{ Path = 'handlers/ip/udp/http3-quic'; Repository = 'xmip-handler-http3-quic' },
    @{ Path = 'handlers/ip/udp/coap'; Repository = 'xmip-handler-coap' }
)

foreach ($Submodule in $Submodules) {
    $Url = "https://github.com/$Owner/$($Submodule.Repository).git"
    if (-not (Test-Path $Submodule.Path)) {
        git submodule add $Url $Submodule.Path
    }
}
