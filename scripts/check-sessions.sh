#!/bin/bash
# Vérifie le modèle des sessions (SessionModel.swift) avec les seuls Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")/.."

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

swiftc -o "${WORK_DIR}/check-sessions" NotchDrop/SessionModel.swift NotchDrop/RequestModel.swift NotchDrop/OwnDragGuard.swift NotchDrop/TrayScroll.swift NotchDrop/NowPlayingModel.swift NotchDrop/BrowserTabsModel.swift Checks/Sessions/main.swift
"${WORK_DIR}/check-sessions"
