#!/bin/zsh
# Vérifie le formatage et les règles de style (.swift-format, toutes les règles activées).
# Avec --fix, reformate les fichiers au lieu de seulement signaler les écarts.
set -euo pipefail
cd "${0:A:h}/.."

sources=(Foulee Packages/FTMSKit/Package.swift Packages/FTMSKit/Sources Packages/FTMSKit/Tests scripts/make-artwork.swift)

if [[ ${1:-} == --fix ]]; then
  swift format --in-place --recursive --parallel $sources
fi
swift format lint --strict --recursive --parallel $sources
echo "Formatage conforme."
