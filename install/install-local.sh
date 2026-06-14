#!/usr/bin/env sh
set -eu

INSTALL_ROOT="${1:-/opt/xmip}"

mkdir -p "$INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT/bin"
mkdir -p "$INSTALL_ROOT/config"
mkdir -p "$INSTALL_ROOT/modules"
mkdir -p "$INSTALL_ROOT/data"
mkdir -p "$INSTALL_ROOT/data/persistence"
mkdir -p "$INSTALL_ROOT/data/management"
mkdir -p "$INSTALL_ROOT/logs"

CONFIG_PATH="$INSTALL_ROOT/config/xmip-node.toml"

if [ ! -f "$CONFIG_PATH" ]; then
cat > "$CONFIG_PATH" <<EOF
[node]
name = "local-xmip-node"
cluster = "local-xmip-cluster"

[storage]
persistence_path = "$INSTALL_ROOT/data/persistence"
management_path = "$INSTALL_ROOT/data/management"

[modules]
load_from = "$INSTALL_ROOT/modules"
EOF
fi

echo "Xmip local layout initialized at $INSTALL_ROOT"
echo "Persistence store: $INSTALL_ROOT/data/persistence"
echo "Management store:   $INSTALL_ROOT/data/management"
