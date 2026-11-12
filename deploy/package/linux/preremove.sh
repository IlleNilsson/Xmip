#!/bin/sh
# Before the .deb or .rpm is removed (nfpm.yaml): xmip-service stops the
# node's unit, waiting for its drain, and removes it. Only on removal — dpkg
# says `remove`, rpm says 0 — never on an upgrade, which postinstall.sh
# restarts. Nothing under /opt/xmip but the package's two files goes:
# configuration, data, audit and logs stay (ADR-0040).
#
# Packaged in the .rpm built 2026-11-11 (nfpm.yaml); no package has been
# removed yet, so it has not run.
set -e

case "$1" in
    remove | 0)
        if [ -f /opt/xmip/config/node.xmip ]; then
            /opt/xmip/bin/xmip-service \
                --configuration /opt/xmip/config/node.xmip \
                --uninstall
        fi
        ;;
esac
