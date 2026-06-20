use crate::handler_universe::{HandlerRepository, HandlerSpace};

pub const NETWORK_HANDLER_REPOSITORIES: &[HandlerRepository] = &[
    HandlerRepository { repository_name: "xmip-handler-file", submodule_path: "handlers/file", space: HandlerSpace::FileTransfer },
    HandlerRepository { repository_name: "xmip-handler-ftp", submodule_path: "handlers/file-transfer/ftp", space: HandlerSpace::FileTransfer },
    HandlerRepository { repository_name: "xmip-handler-tcp-base", submodule_path: "handlers/ip/tcp/base", space: HandlerSpace::NetworkWeb },
    HandlerRepository { repository_name: "xmip-handler-raw-tcp", submodule_path: "handlers/ip/tcp/raw-tcp", space: HandlerSpace::NetworkWeb },
    HandlerRepository { repository_name: "xmip-handler-udp-base", submodule_path: "handlers/ip/udp/base", space: HandlerSpace::NetworkWeb },
    HandlerRepository { repository_name: "xmip-handler-raw-udp", submodule_path: "handlers/ip/udp/raw-udp", space: HandlerSpace::NetworkWeb },
    HandlerRepository { repository_name: "xmip-handler-http", submodule_path: "handlers/ip/tcp/http", space: HandlerSpace::NetworkWeb },
    HandlerRepository { repository_name: "xmip-handler-web-api", submodule_path: "handlers/ip/tcp/http/web-api", space: HandlerSpace::NetworkWeb },
    HandlerRepository { repository_name: "xmip-handler-soap", submodule_path: "handlers/ip/tcp/http/soap", space: HandlerSpace::NetworkWeb },
    HandlerRepository { repository_name: "xmip-handler-websocket", submodule_path: "handlers/ip/tcp/http/websocket", space: HandlerSpace::NetworkWeb },
    HandlerRepository { repository_name: "xmip-handler-grpc", submodule_path: "handlers/ip/tcp/grpc", space: HandlerSpace::NetworkWeb },
    HandlerRepository { repository_name: "xmip-handler-mllp", submodule_path: "handlers/ip/tcp/mllp", space: HandlerSpace::Healthcare },
    HandlerRepository { repository_name: "xmip-handler-http3-quic", submodule_path: "handlers/ip/udp/http3-quic", space: HandlerSpace::NetworkWeb },
    HandlerRepository { repository_name: "xmip-handler-coap", submodule_path: "handlers/ip/udp/coap", space: HandlerSpace::IndustrialIoT },
];
