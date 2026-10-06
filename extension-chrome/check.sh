#!/bin/bash
# Vérifie les fonctions pures de l'extension Chrome (lib.js), avec node.
set -euo pipefail
cd "$(dirname "$0")"
node check.test.js
