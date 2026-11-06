#!/bin/bash
# Tests du package FTMSKit, avertissements bloquants, puis sous Address Sanitizer.
# En bash plutôt qu'en zsh : la CI le lance aussi dans l'image Swift pour Linux.
set -euo pipefail
cd "$(dirname "$0")/.."

swift test --package-path Packages/FTMSKit -Xswiftc -warnings-as-errors
swift test --package-path Packages/FTMSKit -Xswiftc -warnings-as-errors --sanitize=address
