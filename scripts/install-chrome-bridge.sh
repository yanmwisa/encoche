#!/bin/bash
# Installe le pont entre Chrome et l'app Encoche : l'hôte de messagerie native et son manifeste.
# Écrit seulement dans le dossier de l'app (Application Support/Encoche) et dans le dossier des hôtes de
# messagerie native de Chrome ; une copie datée de tout fichier remplacé est gardée à côté.
# L'extension elle-même se charge à la main : Chrome > Extensions > mode développeur > Charger l'extension non empaquetée.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXTENSION_ID="$(tr -d '[:space:]' < "${ROOT}/extension-chrome/EXTENSION_ID")"
STAMP="$(date +%Y%m%d)"

SUPPORT="${HOME}/Library/Application Support/Encoche"
HOST_PATH="${SUPPORT}/encoche-chrome-host.py"
CHROME_HOSTS="${HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts"
MANIFEST_PATH="${CHROME_HOSTS}/local.encoche.chrome.json"

backup_if_present() {
    [ -e "$1" ] && cp -p "$1" "$1.bak-${STAMP}-pont-chrome"
    return 0
}

mkdir -p "${SUPPORT}" "${CHROME_HOSTS}"

backup_if_present "${HOST_PATH}"
cp "${ROOT}/scripts/encoche-chrome-host.py" "${HOST_PATH}"
chmod 755 "${HOST_PATH}"

backup_if_present "${MANIFEST_PATH}"
python3 - "${HOST_PATH}" "${EXTENSION_ID}" "${MANIFEST_PATH}" <<'PY'
import json, sys
host_path, extension_id, manifest_path = sys.argv[1:4]
manifest = {
    "name": "local.encoche.chrome",
    "description": "Pont entre l'extension Encoche de Chrome et l'app Encoche (ce Mac seulement)",
    "path": host_path,
    "type": "stdio",
    "allowed_origins": [f"chrome-extension://{extension_id}/"],
}
with open(manifest_path, "w", encoding="utf-8") as out:
    json.dump(manifest, out, indent=2, ensure_ascii=False)
    out.write("\n")
PY

echo "Hôte installé : ${HOST_PATH}"
echo "Manifeste     : ${MANIFEST_PATH}"
echo "Identifiant de l'extension attendu : ${EXTENSION_ID}"
echo "Reste à charger l'extension : ${ROOT}/extension-chrome"
