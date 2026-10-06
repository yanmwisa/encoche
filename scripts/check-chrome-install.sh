#!/bin/bash
# Vérifie l'installation du pont Chrome dans un HOME jeté : jamais le vrai dossier de Chrome.
set -u
cd "$(dirname "$0")/.."
FAKE_HOME="$(mktemp -d /tmp/encc.XXXXXX)"
trap 'rm -rf "${FAKE_HOME}"' EXIT
passed=0; failed=0
check() { if [ "$2" = "0" ]; then passed=$((passed + 1)); echo "OK   $1"; else failed=$((failed + 1)); echo "ECHEC $1"; fi; }

HOME="${FAKE_HOME}" ./scripts/install-chrome-bridge.sh >/dev/null 2>&1; check "l'installation réussit" "$?"
MANIFEST="${FAKE_HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts/local.encoche.chrome.json"
HOST="${FAKE_HOME}/Library/Application Support/Encoche/encoche-chrome-host.py"
[ -x "${HOST}" ]; check "l'hôte est installé et exécutable" "$?"
python3 - "${MANIFEST}" "${HOST}" "$(tr -d '[:space:]' < extension-chrome/EXTENSION_ID)" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
assert m["name"] == "local.encoche.chrome" and m["type"] == "stdio", m
assert m["path"] == sys.argv[2] and m["path"].startswith("/"), m
assert m["allowed_origins"] == [f"chrome-extension://{sys.argv[3]}/"], m
PY
check "le manifeste nomme seulement notre extension, avec un chemin absolu" "$?"
HOME="${FAKE_HOME}" ./scripts/install-chrome-bridge.sh >/dev/null 2>&1
ls "${FAKE_HOME}/Library/Application Support/Encoche/"encoche-chrome-host.py.bak-* >/dev/null 2>&1; check "une réinstallation garde une copie datée de l'hôte" "$?"
ls "${FAKE_HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts/"local.encoche.chrome.json.bak-* >/dev/null 2>&1; check "une réinstallation garde une copie datée du manifeste" "$?"
python3 -c "import json,sys; m=json.load(open(sys.argv[1])); sys.exit(0 if m['allowed_origins'][0].endswith('/') else 1)" "${MANIFEST}"; check "l'origine autorisée finit par une barre oblique (exigé par Chrome)" "$?"

echo; echo "${passed} réussis, ${failed} échec(s)"
[ "${failed}" = "0" ]
