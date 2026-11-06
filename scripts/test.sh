#!/bin/bash
# Tests du package FTMSKit, avertissements bloquants, puis sous Address Sanitizer.
# En bash plutôt qu'en zsh : la CI le lance aussi dans l'image Swift pour Linux.
set -euo pipefail
cd "$(dirname "$0")/.."

# Sous Linux, Address Sanitizer cherche aussi les fuites mémoire et en signale dans XCTest et dans
# les arguments des tests paramétrés de Swift Testing, jamais dans FTMSKit. La recherche de fuites
# n'existe pas sur macOS : la couper garde la même vérification sur les deux systèmes.
export ASAN_OPTIONS=${ASAN_OPTIONS:-detect_leaks=0}

swift test --package-path Packages/FTMSKit -Xswiftc -warnings-as-errors
swift test --package-path Packages/FTMSKit -Xswiftc -warnings-as-errors --sanitize=address
