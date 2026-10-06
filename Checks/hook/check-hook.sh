#!/bin/bash
# Vérifie le script de hook : il transmet l'événement tel quel avec le pid, et ne gêne jamais Claude Code.
set -u

cd "$(dirname "$0")/../.."
HOOK="$PWD/scripts/encoche-claude-hook.sh"

# Un HOME jeté : le script cherche le socket sous $HOME/Library/Application Support/Encoche.
FAKE_HOME="$(mktemp -d /tmp/enc.XXXXXX)"  # court : un chemin de socket Unix est limité à 103 octets
trap 'kill "${LISTENER_PID:-0}" 2>/dev/null; rm -rf "${FAKE_HOME}"' EXIT
SOCKET_DIR="${FAKE_HOME}/Library/Application Support/Encoche"
SOCKET="${SOCKET_DIR}/sessions.sock"
mkdir -p "${SOCKET_DIR}"

passed=0
failed=0
check() {
    if [ "$2" = "0" ]; then passed=$((passed + 1)); echo "OK   $1"; else failed=$((failed + 1)); echo "ECHEC $1"; fi
}

EVENT='{"hook_event_name":"Stop","session_id":"abc","cwd":"/tmp/projet"}'

# 1. App fermée (pas de socket) : sort avec 0, sans attendre.
start=$(date +%s)
echo "${EVENT}" | HOME="${FAKE_HOME}" "${HOOK}"
code=$?
elapsed=$(( $(date +%s) - start ))
[ "${code}" = "0" ] && [ "${elapsed}" -le 1 ]; check "app fermée : sort avec 0 en moins d'une seconde" "$?"

# 2. Socket sans personne derrière (app plantée) : sort avec 0 aussi.
python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "${SOCKET}"
start=$(date +%s)
echo "${EVENT}" | HOME="${FAKE_HOME}" "${HOOK}"
code=$?
elapsed=$(( $(date +%s) - start ))
[ "${code}" = "0" ] && [ "${elapsed}" -le 2 ]; check "socket sans écoute : sort avec 0 en moins de deux secondes" "$?"
rm -f "${SOCKET}"

# 3. App ouverte : l'événement arrive complet, enveloppé avec le pid.
RECEIVED="${FAKE_HOME}/received.json"
/usr/bin/nc -l -U "${SOCKET}" > "${RECEIVED}" &
LISTENER_PID=$!
sleep 0.5
echo "${EVENT}" | HOME="${FAKE_HOME}" "${HOOK}"
code=$?
sleep 0.5
[ "${code}" = "0" ]; check "app ouverte : sort avec 0" "$?"
python3 - "${RECEIVED}" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["event"]["session_id"] == "abc", data
assert data["event"]["hook_event_name"] == "Stop", data
assert isinstance(data["claude_pid"], int) and data["claude_pid"] > 0, data
PY
check "l'événement arrive intact avec le pid du parent" "$?"

# 4. Autorisation : le script attend la réponse de l'app et sort la décision de Claude Code.
rm -f "${SOCKET}"
# Une fausse app : reçoit l'événement, répond ce que dit REPLY (allow, deny ou rien).
cat > "${FAKE_HOME}/fake-app.py" <<'PY'
import json, os, socket, sys, time
sock_path, replies_dir, mode, out = sys.argv[1:5]
srv = socket.socket(socket.AF_UNIX); srv.bind(sock_path); srv.listen(4); srv.settimeout(10)
conn, _ = srv.accept()
data = b""
while True:
    chunk = conn.recv(4096)
    if not chunk: break
    data += chunk
msg = json.loads(data)
open(out, "w").write(json.dumps(msg))
if mode != "silence":
    time.sleep(0.2)
    fd = os.open(os.path.join(replies_dir, msg["reply_id"]), os.O_WRONLY | os.O_NONBLOCK)
    os.write(fd, (mode + "\n").encode()); os.close(fd)
PY
PERMISSION='{"hook_event_name":"PermissionRequest","session_id":"abc","cwd":"/tmp/projet","tool_name":"Bash","tool_input":{"command":"git push"}}'
REPLIES="${SOCKET_DIR}/replies"

for MODE in allow deny; do
    rm -f "${SOCKET}"
    python3 "${FAKE_HOME}/fake-app.py" "${SOCKET}" "${REPLIES}" "${MODE}" "${FAKE_HOME}/req-${MODE}.json" &
    APP_PID=$!
    sleep 0.5
    OUTPUT="$(echo "${PERMISSION}" | HOME="${FAKE_HOME}" "${HOOK}")"
    wait "${APP_PID}" 2>/dev/null
    python3 - "${OUTPUT}" "${MODE}" "${FAKE_HOME}/req-${MODE}.json" <<'PY'
import json, sys
out = json.loads(sys.argv[1])["hookSpecificOutput"]
assert out["hookEventName"] == "PermissionRequest", out
assert out["decision"]["behavior"] == sys.argv[2], out
sent = json.load(open(sys.argv[3]))
assert sent["event"]["tool_name"] == "Bash" and len(sent["reply_id"]) >= 8, sent
PY
    check "autorisation : « ${MODE} » de l'app devient la décision de Claude Code" "$?"
done

# 5. Sans réponse : sort sans rien dire, et le tube est retiré.
rm -f "${SOCKET}"
python3 "${FAKE_HOME}/fake-app.py" "${SOCKET}" "${REPLIES}" silence "${FAKE_HOME}/req-silence.json" &
APP_PID=$!
sleep 0.5
start=$(date +%s)
OUTPUT="$(echo "${PERMISSION}" | HOME="${FAKE_HOME}" ENCOCHE_APPROVAL_TIMEOUT=1 "${HOOK}")"
code=$?
elapsed=$(( $(date +%s) - start ))
wait "${APP_PID}" 2>/dev/null
[ "${code}" = "0" ] && [ -z "${OUTPUT}" ] && [ "${elapsed}" -le 3 ]; check "sans réponse : sort avec 0, sans sortie, après le délai" "$?"
[ -z "$(ls -A "${REPLIES}")" ]; check "le tube de réponse est retiré à la sortie" "$?"
[ "$(stat -f '%Lp' "${REPLIES}")" = "700" ]; check "le dossier des réponses est en 0700" "$?"

# 5b. Un tube resté d'un script tué est nettoyé au passage suivant.
mkfifo "${REPLIES}/ancien-12345678"
touch -t 202001010000 "${REPLIES}/ancien-12345678"
rm -f "${SOCKET}"
python3 "${FAKE_HOME}/fake-app.py" "${SOCKET}" "${REPLIES}" silence "${FAKE_HOME}/req-clean.json" &
APP_PID=$!
sleep 0.5
echo "${PERMISSION}" | HOME="${FAKE_HOME}" ENCOCHE_APPROVAL_TIMEOUT=1 "${HOOK}" >/dev/null
wait "${APP_PID}" 2>/dev/null
[ ! -e "${REPLIES}/ancien-12345678" ]; check "un tube abandonné depuis plus de deux minutes est supprimé" "$?"

# 5c. Des étapes proposées : le script sort la ligne de numéros choisis, et rien si la réponse n'a pas la forme attendue.
STEPS='{"hook_event_name":"NextSteps","session_id":"abc","cwd":"/tmp/projet","items":[{"label":"Tests","prompt":"lance"},{"label":"Commit","prompt":"commit"}]}'
for ANSWER in "1,0" "0" "rm -rf" "1,,0"; do
    rm -f "${SOCKET}"
    python3 "${FAKE_HOME}/fake-app.py" "${SOCKET}" "${REPLIES}" "${ANSWER}" "${FAKE_HOME}/req-steps.json" &
    APP_PID=$!
    sleep 0.5
    OUTPUT="$(echo "${STEPS}" | HOME="${FAKE_HOME}" "${HOOK}")"
    wait "${APP_PID}" 2>/dev/null
    case "${ANSWER}" in
        "1,0"|"0") [ "${OUTPUT}" = "${ANSWER}" ]; check "étapes : « ${ANSWER} » sort tel quel" "$?" ;;
        *) [ -z "${OUTPUT}" ]; check "étapes : la réponse « ${ANSWER} » est ignorée" "$?" ;;
    esac
done
python3 - "${FAKE_HOME}/req-steps.json" <<'PY'
import json, sys
sent = json.load(open(sys.argv[1]))
assert sent["event"]["hook_event_name"] == "NextSteps" and len(sent["reply_id"]) >= 8, sent
PY
check "les étapes arrivent à l'app avec leur canal de réponse" "$?"

# 5d. Une question de Claude (AskUserQuestion) arrive comme autorisation : transmise sans attendre de réponse.
QUESTION='{"hook_event_name":"PermissionRequest","session_id":"abc","cwd":"/tmp/projet","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Couleur ?"}]}}'
rm -f "${SOCKET}"
/usr/bin/nc -l -U "${SOCKET}" > "${FAKE_HOME}/question.json" &
LISTENER_PID=$!
sleep 0.5
start=$(date +%s)
OUTPUT="$(echo "${QUESTION}" | HOME="${FAKE_HOME}" "${HOOK}")"
elapsed=$(( $(date +%s) - start ))
sleep 0.3
[ -z "${OUTPUT}" ] && [ "${elapsed}" -le 2 ]; check "question de Claude : sort tout de suite, sans décision" "$?"
python3 - "${FAKE_HOME}/question.json" <<'PY'
import json, sys
sent = json.load(open(sys.argv[1]))
assert sent["event"]["tool_name"] == "AskUserQuestion" and "reply_id" not in sent, sent
PY
check "question de Claude : transmise à l'app sans canal de réponse" "$?"

# 6. App qui a disparu : une autorisation ne bloque pas.
rm -f "${SOCKET}"
python3 -c "import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1])" "${SOCKET}"
start=$(date +%s)
echo "${PERMISSION}" | HOME="${FAKE_HOME}" "${HOOK}"
code=$?
elapsed=$(( $(date +%s) - start ))
[ "${code}" = "0" ] && [ "${elapsed}" -le 3 ]; check "autorisation sans app derrière : sort tout de suite" "$?"

# 7. Un autre événement qui cite le mot-clé de l'autorisation dans son texte n'attend jamais.
rm -f "${SOCKET}"
/usr/bin/nc -l -U "${SOCKET}" > "${FAKE_HOME}/other.json" &
LISTENER_PID=$!
sleep 0.5
start=$(date +%s)
echo '{"hook_event_name":"PostToolUse","session_id":"abc","cwd":"/tmp","tool_input":{"command":"echo \"hook_event_name\":\"PermissionRequest\""}}' | HOME="${FAKE_HOME}" "${HOOK}"
elapsed=$(( $(date +%s) - start ))
[ "${elapsed}" -le 2 ]; check "un événement ordinaire qui cite le mot « PermissionRequest » n'attend pas" "$?"

echo
echo "${passed} réussis, ${failed} échec(s)"
[ "${failed}" = "0" ]
