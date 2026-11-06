#!/bin/zsh
# Produit dist/Foulee-<version>.zip et dist/Foulee-<version>.dmg, signés ad hoc (non notarisés).
# Usage : scripts/package.sh <version> [numéro de build]
set -euo pipefail
cd "${0:A:h}/.."

version=${1:?Usage : scripts/package.sh <version> [numéro de build]}
FOULEE_ADHOC=1 FOULEE_VERSION=$version FOULEE_BUILD=${2:-1} ./build.sh

rm -rf dist
mkdir dist
ditto -c -k --norsrc --noextattr --keepParent build/Foulee.app "dist/Foulee-$version.zip"

# dmgbuild écrit la mise en page de la fenêtre (fond, position des icônes) sans piloter le Finder.
if [[ ! -x build/venv/bin/dmgbuild ]]; then
  /usr/bin/python3 -m venv build/venv
  build/venv/bin/pip install --quiet --disable-pip-version-check dmgbuild
fi
build/venv/bin/dmgbuild -s Support/dmg-settings.py \
  -D app=build/Foulee.app -D background=Support/dmg-background.tiff \
  Foulée "dist/Foulee-$version.dmg"

ls -lh dist
