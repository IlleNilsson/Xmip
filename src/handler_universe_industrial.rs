use crate::handler_universe::{HandlerRepository, HandlerSpace};

pub const INDUSTRIAL_HANDLER_REPOSITORIES: &[HandlerRepository] = &[
    HandlerRepository { repository_name: "xmip-handler-industrial-device-common", submodule_path: "handlers/industrial-device/common", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-canbus", submodule_path: "handlers/industrial-device/canbus", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-opc-ua", submodule_path: "handlers/industrial-device/opc-ua", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-modbus", submodule_path: "handlers/industrial-device/modbus", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-mqtt", submodule_path: "handlers/industrial-device/mqtt", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-mqtt-sn", submodule_path: "handlers/industrial-device/mqtt-sn", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-profinet", submodule_path: "handlers/industrial-device/profinet", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-ethernet-ip", submodule_path: "handlers/industrial-device/ethernet-ip", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-bacnet", submodule_path: "handlers/industrial-device/bacnet", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-dnp3", submodule_path: "handlers/industrial-device/dnp3", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-iec-60870-5-104", submodule_path: "handlers/industrial-device/iec-60870-5-104", space: HandlerSpace::EnergyUtilities },
    HandlerRepository { repository_name: "xmip-handler-iec-61850", submodule_path: "handlers/industrial-device/iec-61850", space: HandlerSpace::EnergyUtilities },
    HandlerRepository { repository_name: "xmip-handler-knx", submodule_path: "handlers/industrial-device/knx", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-lorawan", submodule_path: "handlers/industrial-device/lorawan", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-zigbee", submodule_path: "handlers/industrial-device/zigbee", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-ble", submodule_path: "handlers/industrial-device/ble", space: HandlerSpace::IndustrialIoT },
    HandlerRepository { repository_name: "xmip-handler-ocpp", submodule_path: "handlers/energy/ocpp", space: HandlerSpace::EnergyUtilities },
];
