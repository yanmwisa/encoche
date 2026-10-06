# ADR 0001 — Les sessions Claude Code dans l'encoche

Statut : accepté (3 octobre 2026)

## Contexte

Plusieurs sessions Claude Code tournent en même temps. Aucune ne prévient laquelle attend une réponse ou une autorisation. L'encoche est toujours visible : c'est l'endroit où le dire.

## Décision

1. **Source des événements** : les hooks de Claude Code (`SessionStart`, `UserPromptSubmit`, `PermissionRequest`, `Notification`, `PostToolUse`, `Stop`, `SessionEnd`) lancent un petit script shell qui transmet l'événement à l'app. `PostToolUse` sert à repasser une session en « travaille » une fois l'autorisation donnée ; vérifié sur une vraie session (mêmes champs que ceux lus par l'app).
2. **Canal** : un socket Unix dans `~/Library/Application Support/Encoche/` (dossier en 0700, socket en 0600), une connexion par événement, lecture bornée à 64 Ko. Pas de réseau, pas de port.
3. **Le script ne gêne jamais Claude Code** : il sort toujours avec 0, en moins d'une seconde, y compris app fermée.
4. **Modèle pur** : l'état des sessions et les décisions d'affichage (phase, tri, texte des oreilles) sont des fonctions sans effet de bord, dans un fichier qui n'importe que Foundation, testé à part.
5. **Lecture seule** : l'encoche montre et amène à la session. Elle n'autorise ni ne refuse rien, et ne répond pas à une question.
6. **« Y aller »** : ouvre la session précise dans l'application Claude (`claude://claude.ai/epitaxy/<id>`, retrouvé par `cliSessionId` dans `claude-code-sessions/`, lecture seule). Sans correspondance (terminal), active seulement l'application hôte, sans choisir l'onglet.
7. **Écrit à nouveau, pas copié** : claude-peek (README MIT, sans fichier de licence) sert de référence pour les champs des événements.

## Conséquences

- Brancher les hooks demande de modifier `~/.claude/settings.json` : accord explicite et sauvegarde à chaque fois.
- ChatGPT (site ou application) n'envoie aucun événement lisible : non détectable. Codex est possible plus tard.
- Tout processus du même utilisateur peut écrire dans le socket : on borne et on nettoie les textes affichés.

## Alternatives écartées

- Surveiller les fichiers de transcription : lecture de contenus privés, et rien ne dit qu'une session attend.
- vibe-notch : envoie des statistiques d'usage et se met à jour tout seul.
- Un port TCP local : exposé à tout le réseau local si mal lié.

## Répondre depuis l'encoche (3 octobre 2026)

- Une **demande** est soit une autorisation d'outil (hook `PermissionRequest`), soit des **étapes proposées** par le mod `next-steps-sequence` (événement `NextSteps`, envoyé par le mod, pas par Claude Code).
- Le script de hook crée un tube nommé privé (`replies/`, dossier 0700), envoie la demande avec son identifiant, attend la réponse (60 s pour une autorisation, 10 min pour des étapes), puis sort la décision de Claude Code ou la ligne de numéros. Sans réponse, la demande reste dans la session.
- L'encoche ne renvoie que `allow`, `deny` ou des numéros d'étapes : le texte des étapes ne quitte jamais le mod, qui valide les numéros avant de lancer la séquence.
- Les étapes n'allument pas les oreilles : elles attendent dans l'écran Sessions.

