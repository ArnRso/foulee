#!/bin/zsh
# Compile Foulée avec xcodebuild (Release) et place l'app dans build/Foulee.app.
# Avec --install, la copie aussi dans /Applications (emplacement stable pour l'ouverture à la connexion).
# Variables optionnelles (utilisées pour les releases) :
#   FOULEE_ADHOC=1        signature ad hoc même si une équipe est configurée
#   FOULEE_VERSION=1.2.0  version affichée (MARKETING_VERSION)
#   FOULEE_BUILD=42       numéro de build (CURRENT_PROJECT_VERSION)
set -euo pipefail
cd "${0:A:h}"

# Utilise Xcode même si xcode-select pointe encore vers les Command Line Tools.
if ! xcodebuild -version &>/dev/null; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Sans équipe choisie dans Xcode (Signing & Capabilities), on signe en ad hoc :
# macOS redemandera alors l'autorisation Bluetooth après chaque compilation.
settings=()
if [[ ${FOULEE_ADHOC:-} == 1 ]] || ! grep -q 'DEVELOPMENT_TEAM = [A-Z0-9]' Foulee.xcodeproj/project.pbxproj; then
  settings+=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi
[[ -n ${FOULEE_VERSION:-} ]] && settings+=(MARKETING_VERSION=$FOULEE_VERSION)
[[ -n ${FOULEE_BUILD:-} ]] && settings+=(CURRENT_PROJECT_VERSION=$FOULEE_BUILD)

xcodebuild -project Foulee.xcodeproj -scheme Foulee -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData -allowProvisioningUpdates -quiet \
  "${settings[@]}" build

# Quitte proprement l'instance remplacée (Stop envoyé au tapis, déconnexion) : sinon `open`
# se contenterait de réactiver l'ancienne version. Une instance lancée ailleurs est laissée tranquille.
running=$(pgrep -x Foulee | head -1 || true)
if [[ -n $running ]] && { [[ ${1:-} == --install ]] || ps -o command= -p "$running" | grep -q "^$PWD/build/"; }; then
  osascript -e 'quit app id "com.arnrso.foulee"'
  while pgrep -xq Foulee; do sleep 0.1; done
fi

rm -rf build/Foulee.app
cp -R build/DerivedData/Build/Products/Release/Foulee.app build/
app=build/Foulee.app
if [[ ${1:-} == --install ]]; then
  rm -rf /Applications/Foulee.app
  cp -R build/Foulee.app /Applications/
  app=/Applications/Foulee.app
fi

echo "OK : $app ($(codesign -dvv "$app" 2>&1 | grep -E '^(Authority|Signature)=' | head -1))"
