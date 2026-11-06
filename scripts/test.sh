#!/bin/zsh
# Tests du package FTMSKit, avertissements bloquants, puis sous Address Sanitizer.
set -euo pipefail
cd "${0:A:h}/.."

swift test --package-path Packages/FTMSKit -Xswiftc -warnings-as-errors
swift test --package-path Packages/FTMSKit -Xswiftc -warnings-as-errors --sanitize=address
