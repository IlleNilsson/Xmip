#!/bin/sh
# After the .deb or .rpm is unpacked (nfpm.yaml): xmip-service lays the node
# out and registers it — the starter /opt/xmip/config/xmip.toml where there
# is none, the node's slice, the folders, the systemd unit registration.rs
# writes, started; its RuntimeDirectory makes /run/xmip for the node's
# account, where its local endpoint is. An upgrade finds its configuration and keeps it, and the
# unit is restarted on the new program.
#
# XMIP_NODE and XMIP_CLUSTER name the node and the cluster, each the host's
# short name unless set; the cluster is used where the machine's xmip.toml
# names none. XMIP_ACCOUNT names the account the node's service runs as,
# root unless set (ADR-0015 and ADR-0028, amendments 2026-10-21).
#
# WRITTEN, NOT RUN: builds are Windows-only for now (nfpm.yaml).
set -e

node="${XMIP_NODE:-$(hostname -s)}"
cluster="${XMIP_CLUSTER:-$node}"

if [ -n "${XMIP_ACCOUNT:-}" ]; then
    /opt/xmip/bin/xmip-service \
        --configuration /opt/xmip/config/xmip.toml \
        --node "$node" \
        --cluster "$cluster" \
        --account "$XMIP_ACCOUNT" \
        --install
else
    /opt/xmip/bin/xmip-service \
        --configuration /opt/xmip/config/xmip.toml \
        --node "$node" \
        --cluster "$cluster" \
        --install
fi
