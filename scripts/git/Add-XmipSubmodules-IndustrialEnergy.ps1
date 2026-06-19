param([Parameter(Mandatory = $true)][string] $Owner)

$Submodules = @(
    @{ Path = 'handlers/industrial-device/common'; Repository = 'xmip-handler-industrial-device-common' },
    @{ Path = 'handlers/industrial-device/canbus'; Repository = 'xmip-handler-canbus' },
    @{ Path = 'handlers/industrial-device/opc-ua'; Repository = 'xmip-handler-opc-ua' },
    @{ Path = 'handlers/industrial-device/modbus'; Repository = 'xmip-handler-modbus' },
    @{ Path = 'handlers/industrial-device/mqtt'; Repository = 'xmip-handler-mqtt' },
    @{ Path = 'handlers/industrial-device/mqtt-sn'; Repository = 'xmip-handler-mqtt-sn' },
    @{ Path = 'handlers/industrial-device/profinet'; Repository = 'xmip-handler-profinet' },
    @{ Path = 'handlers/industrial-device/ethernet-ip'; Repository = 'xmip-handler-ethernet-ip' },
    @{ Path = 'handlers/industrial-device/bacnet'; Repository = 'xmip-handler-bacnet' },
    @{ Path = 'handlers/industrial-device/dnp3'; Repository = 'xmip-handler-dnp3' },
    @{ Path = 'handlers/industrial-device/iec-60870-5-104'; Repository = 'xmip-handler-iec-60870-5-104' },
    @{ Path = 'handlers/industrial-device/iec-61850'; Repository = 'xmip-handler-iec-61850' },
    @{ Path = 'handlers/industrial-device/knx'; Repository = 'xmip-handler-knx' },
    @{ Path = 'handlers/industrial-device/lorawan'; Repository = 'xmip-handler-lorawan' },
    @{ Path = 'handlers/industrial-device/zigbee'; Repository = 'xmip-handler-zigbee' },
    @{ Path = 'handlers/industrial-device/ble'; Repository = 'xmip-handler-ble' },
    @{ Path = 'handlers/energy/ocpp'; Repository = 'xmip-handler-ocpp' }
)

foreach ($Submodule in $Submodules) {
    $Url = "https://github.com/$Owner/$($Submodule.Repository).git"
    if (-not (Test-Path $Submodule.Path)) {
        git submodule add $Url $Submodule.Path
    }
}
