#!/bin/bash
# Vérifie la réception des sessions : le vrai script de hook, le vrai socket Unix, le vrai décodage.
set -euo pipefail

cd "$(dirname "$0")/.."

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

swiftc -o "${WORK_DIR}/check-server" \
    NotchDrop/SessionModel.swift NotchDrop/RequestModel.swift NotchDrop/RequestReplyChannel.swift NotchDrop/UnixSocketListener.swift NotchDrop/SessionSocketServer.swift Checks/Server/main.swift
"${WORK_DIR}/check-server" "$PWD/scripts/encoche-claude-hook.sh"
