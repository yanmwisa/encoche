#!/bin/bash
# Vérifie le pont avec Chrome : le vrai hôte de messagerie native, le vrai socket, le vrai décodage.
set -euo pipefail

cd "$(dirname "$0")/.."

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

swiftc -o "${WORK_DIR}/check-browser" \
    NotchDrop/SessionModel.swift NotchDrop/RequestModel.swift NotchDrop/NowPlayingModel.swift NotchDrop/BrowserTabsModel.swift \
    NotchDrop/UnixSocketListener.swift NotchDrop/BrowserBridgeServer.swift Checks/Browser/main.swift
"${WORK_DIR}/check-browser" "$PWD/scripts/encoche-chrome-host.py"
