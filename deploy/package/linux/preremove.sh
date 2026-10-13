#!/bin/sh
# Before the .deb or .rpm is removed (nfpm.yaml): xmip-service stops the
# node's unit, waiting for its drain, and removes it. Only on removal — dpkg
# says `remove`, rpm says 0 — never on an upgrade, which postinstall.sh
# restarts. Nothing under /opt/xmip but the package's two files goes:
# configuration, data, audit and logs stay (ADR-0040).
#
# WRITTEN, NOT RUN: builds are Windows-only for now (nfpm.yaml).
set -e

case "$1" in
    remove | 0)
        if [ -f /opt/xmip/config/xmip-node.toml ]; then
            /opt/xmip/bin/xmip-service \
                --configuration /opt/xmip/config/xmip-node.toml \
                --uninstall
        fi
        ;;
esac
