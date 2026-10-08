#!/bin/bash
# Vérifie qu'aucun effet de Pow ne lit ses images : build-app.sh ne peut pas les livrer là où Pow les cherche
# (racine de l'app, refusée par codesign), et l'app plante au lancement dès que .build n'existe plus.
set -u
cd "$(dirname "$0")/.."

# Les effets de Pow 1.0.6 qui chargent Pow_Pow.bundle : Poof.swift, Anvil.swift, SmokeEffect.swift.
bundle_effects="$(grep -rnE '\.(poof|anvil|smoke)\b' NotchDrop --include='*.swift')"
if [ -n "${bundle_effects}" ]; then
    echo "ÉCHEC : effet Pow qui lit Pow_Pow.bundle (plantage de l'app construite) :"
    echo "${bundle_effects}"
    exit 1
fi
echo "OK : aucun effet Pow ne lit Pow_Pow.bundle"
