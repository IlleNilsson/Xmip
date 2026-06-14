#!/usr/bin/env sh
set -eu

INSTALL_ROOT="${1:-/opt/xmip}"

mkdir -p "$INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT/bin"
mkdir -p "$INSTALL_ROOT/config"
mkdir -p "$INSTALL_ROOT/modules"
mkdir -p "$INSTALL_ROOT/data"
mkdir -p "$INSTALL_ROOT/data/persistence-rocksdb"
mkdir -p "$INSTALL_ROOT/logs"

touch "$INSTALL_ROOT/data/management.sqlite"

CONFIG_PATH="$INSTALL_ROOT/config/xmip-node.toml"

if [ ! -f "$CONFIG_PATH" ]; then
cat > "$CONFIG_PATH" <<EOF
[node]
name = "local-xmip-node"
cluster = "local-xmip-cluster"

[storage]
persistence_engine = "rocksdb"
persistence_path = "$INSTALL_ROOT/data/persistence-rocksdb"
management_engine = "sqlite"
management_path = "$INSTALL_ROOT/data/management.sqlite"

[modules]
load_from = "$INSTALL_ROOT/modules"
EOF
fi

echo "Xmip local layout initialized at $INSTALL_ROOT"
echo "Persistence store: $INSTALL_ROOT/data/persistence-rocksdb"
echo "Management store:   $INSTALL_ROOT/data/management.sqlite"
