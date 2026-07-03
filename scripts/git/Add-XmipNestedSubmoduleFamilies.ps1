param(
    [Parameter(Mandatory = $true)]
    [string] $Owner
)

$Families = @(
    @{ Path = 'core'; Repository = 'xmip-core' },
    @{ Path = 'handlers/common'; Repository = 'xmip-handlers-common' },
    @{ Path = 'handlers/messaging'; Repository = 'xmip-handlers-messaging' },
    @{ Path = 'handlers/device'; Repository = 'xmip-handlers-device' },
    @{ Path = 'handlers/industrial'; Repository = 'xmip-handlers-industrial' },
    @{ Path = 'handlers/marine'; Repository = 'xmip-handlers-marine' },
    @{ Path = 'handlers/healthcare'; Repository = 'xmip-handlers-healthcare' },
    @{ Path = 'handlers/business'; Repository = 'xmip-handlers-business' },
    @{ Path = 'handlers/desktop'; Repository = 'xmip-handlers-desktop' },
    @{ Path = 'runtimes'; Repository = 'xmip-runtimes' },
    @{ Path = 'platforms'; Repository = 'xmip-platforms' }
)

foreach ($Family in $Families) {
    $Url = "https://github.com/$Owner/$($Family.Repository).git"
    if (-not (Test-Path $Family.Path)) {
        git submodule add $Url $Family.Path
    }
}

git submodule update --init --recursive
