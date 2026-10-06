#!/bin/sh
# Transmet un événement de Claude Code à l'app Encoche par un socket Unix.
# Ne gêne jamais Claude Code : sort toujours avec 0, vite, même si l'app est fermée.
# Seules exceptions voulues, qui attendent la réponse de l'encoche :
#  - une demande d'autorisation de Claude Code (60 s au plus) : le script sort la décision de Claude Code ;
#  - des étapes proposées, envoyées par le mod next-steps-sequence (10 minutes au plus) : le script sort la
#    ligne de numéros choisis, par exemple « 2,0 ».
# Sans réponse, le script sort sans rien dire et la demande reste posée dans la session, comme avant.

SUPPORT="$HOME/Library/Application Support/Encoche"
SOCKET="$SUPPORT/sessions.sock"

# App fermée : rien à faire.
[ -S "$SOCKET" ] || exit 0

EVENT="$(cat)"

# Le pid du parent permet à l'app de retrouver la fenêtre qui héberge la session.
# Dans un texte JSON, un guillemet du contenu est précédé d'une barre oblique : seul le vrai champ correspond ici.
# Une question de Claude (AskUserQuestion) arrive aussi comme demande d'autorisation, mais n'a rien à autoriser :
# on la signale sans attendre de réponse.
if printf '%s' "$EVENT" | grep -q '"tool_name" *: *"AskUserQuestion"'; then
    printf '{"claude_pid":%s,"event":%s}' "$PPID" "$EVENT" \
        | /usr/bin/nc -U -w 1 "$SOCKET" >/dev/null 2>&1
    exit 0
fi

if printf '%s' "$EVENT" | grep -q '"hook_event_name" *: *"PermissionRequest"'; then
    WAIT_SECONDS=60
elif printf '%s' "$EVENT" | grep -q '"hook_event_name" *: *"NextSteps"'; then
    WAIT_SECONDS=600
else
    printf '{"claude_pid":%s,"event":%s}' "$PPID" "$EVENT" \
        | /usr/bin/nc -U -w 1 "$SOCKET" >/dev/null 2>&1
    exit 0
fi

# Le tube nommé où l'app écrira la réponse : dossier réservé à l'utilisateur, nom aléatoire.
REPLY_ID="$(/usr/bin/uuidgen)"
REPLY_DIR="$SUPPORT/replies"
REPLY_PIPE="$REPLY_DIR/$REPLY_ID"
mkdir -p "$REPLY_DIR" && chmod 700 "$REPLY_DIR" && mkfifo -m 600 "$REPLY_PIPE" || exit 0
# Les tubes d'un script tué avant sa sortie : plus personne ne les attend au bout de deux minutes.
/usr/bin/find "$REPLY_DIR" -type p -mmin +2 -delete 2>/dev/null
trap 'rm -f "$REPLY_PIPE"' EXIT

# Ouvert en lecture et écriture : ne bloque pas, et l'app trouve un lecteur dès qu'elle écrit.
exec 3<>"$REPLY_PIPE"

printf '{"claude_pid":%s,"reply_id":"%s","event":%s}' "$PPID" "$REPLY_ID" "$EVENT" \
    | /usr/bin/nc -U -w 1 "$SOCKET" >/dev/null 2>&1 || exit 0

read -r -t "${ENCOCHE_APPROVAL_TIMEOUT:-$WAIT_SECONDS}" ANSWER <&3 || exit 0

# Des étapes : la ligne de numéros, telle quelle si elle en a la forme, rien sinon.
if [ "$WAIT_SECONDS" = 600 ]; then
    case "$ANSWER" in
        ''|*[!0-9,]*|,*|*,|*,,*) ;;
        *) printf '%s\n' "$ANSWER" ;;
    esac
    exit 0
fi

case "$ANSWER" in
    allow)
        printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n'
        ;;
    deny)
        printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Refusé depuis l’encoche."}}}\n'
        ;;
esac
exit 0
