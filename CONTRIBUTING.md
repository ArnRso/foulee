# Contribuer à Foulée

Ce document s'adresse à qui veut compiler Foulée, la modifier ou publier une version. Pour
utiliser l'app, voir le [README](README.md).

## Organisation du dépôt

| Dossier | Contenu |
|---|---|
| [Foulee/](Foulee) | L'app (SwiftUI, barre des menus) : connexion Bluetooth et pilotage ([TreadmillController.swift](Foulee/TreadmillController.swift)), stockage des séances ([SessionStore.swift](Foulee/SessionStore.swift)), fenêtres Statistiques, Réglages et Diagnostic, raccourcis clavier, mises à jour. |
| [Packages/FTMSKit/](Packages/FTMSKit) | Le protocole FTMS, sans dépendance au reste de l'app : décodage des trames, commandes du Control Point, bornage de la vitesse, découpage en séances, statistiques. Testé avec `swift test`. |
| [poc/](poc/README.md) | Le prototype Python qui a servi à valider le protocole sur le tapis, avec les trames relevées. |
| [Support/](Support) | Info.plist, notes de version, mise en page du `.dmg`. |
| [scripts/](scripts) | Formatage, tests, empaquetage, génération de l'icône. |

Foulée repose sur le protocole Bluetooth standard FTMS (Fitness Machine Service, `0x1826`) via
CoreBluetooth. Ce que le tapis de référence (module FitShow `FS-37FBED`) annonce et accepte est
documenté dans le [README du POC](poc/README.md).

## Compiler et lancer

Avec Xcode : ouvrir `Foulee.xcodeproj` et lancer le schéma **Foulee** (⌘R).
Pour signer avec son Apple ID, choisir son équipe dans la cible Foulee → Signing & Capabilities.

En ligne de commande (Release, dans `build/Foulee.app`) :

```sh
./build.sh
open build/Foulee.app
```

`FOULEE_ADHOC=1 ./build.sh` force la signature ad hoc, sans passer par Apple. Pour installer
dans `/Applications` :

```sh
./build.sh --install
```

`build.sh` quitte proprement l'instance de Foulée lancée depuis `build/` (ou depuis
`/Applications` avec `--install`) avant de la remplacer : **cela envoie Stop au tapis s'il
tourne.**

Sans équipe choisie, l'app est signée ad hoc et macOS peut redemander l'autorisation Bluetooth
après chaque compilation. Pour la réinitialiser :

```sh
tccutil reset BluetoothAlways com.arnrso.foulee
```

Journaux de l'app :

```sh
log stream --predicate 'subsystem == "com.arnrso.foulee"'
```

## Qualité du code

Règles les plus strictes, vérifiées par la CI ([ci.yml](.github/workflows/ci.yml)) sur chaque
pull request, à lancer aussi en local avant de pousser :

- **Formatage et style** : `swift format` avec toutes les règles activées
  ([.swift-format](.swift-format)). `scripts/lint.sh` vérifie, `scripts/lint.sh --fix` reformate.
- **Tests** : FTMSKit, avec Swift Testing, sur des trames réelles du tapis, puis sous Address
  Sanitizer : `scripts/test.sh`.
- **Compilation** : Swift 6 en concurrence stricte, sûreté mémoire explicite (`unsafe`),
  `ExistentialAny`, `InternalImportsByDefault`, `MemberImportVisibility`, avertissements
  bloquants.
- **Dépendances** : Dependabot propose chaque semaine les mises à jour de Sparkle,
  KeyboardShortcuts et des actions GitHub (épinglées par empreinte).

### Machines de la CI

Le formatage et les tests tournent sur Linux, dans l'image Swift officielle épinglée à la
version utilisée en local (`swift --version`). Elle est à mettre à jour à la main dans
`ci.yml` avec la chaîne d'outils du Mac : Dependabot ne suit pas les images des workflows.
Seule la compilation de l'app utilise une machine macOS, parfois longue à obtenir chez GitHub.

Sous Linux, `scripts/test.sh` désactive la recherche de fuites d'Address Sanitizer : elle
signale des fuites dans XCTest et Swift Testing, jamais dans FTMSKit, et n'existe pas sur macOS.

Pour reproduire la CI Linux en local (le volume `foulee-linux-build` garde la compilation
Linux à part de celle du Mac) :

```sh
docker run --rm -v "$PWD":/src -v foulee-linux-build:/src/Packages/FTMSKit/.build -w /src swift:6.4.2-noble scripts/test.sh
```

## Séances : format et stockage

### Fichiers

Une séance par fichier JSON, dans le dossier choisi (par défaut iCloud Drive › Foulee), nommé
`session_AAAA-MM-JJ_HH-MM-SS.json` d'après l'heure locale de début. Noms ASCII sans espace.

- Le format actuel est la **version 3** (`formatVersion`) : JSON sans indentation, totaux,
  événements (démarrage, pause, arrêt, consignes envoyées par Foulée, pertes de connexion) et
  relevés rangés en colonnes (`sampleColumns`, un tableau par mesure, instants au dixième de
  seconde). Environ 120 Ko par heure de marche.
- Les versions 1 et 2 (relevés en objets répétés, `samples`) sont relues, puis réécrites en
  version 3 à leur première lecture. Le décodage est dans
  [TreadmillSession.swift](Packages/FTMSKit/Sources/FTMSKit/TreadmillSession.swift) : toute
  évolution du format doit garder la lecture des versions précédentes et l'incrémenter.
- Les changements de vitesse faits à la télécommande ne sont pas signalés par le tapis : ils
  sont retrouvés dans les relevés (`speedChanges`).
- Une séance interrompue par la fermeture de l'app est marquée `isInterrupted`.

Foulée n'est pas sandboxée : elle écrit directement dans le dossier iCloud Drive, que macOS
synchronise, sans conteneur iCloud ni entitlement. Un conteneur iCloud exigerait une signature
par une équipe Apple, incompatible avec les releases signées ad hoc.

### Pourquoi des fichiers JSON et pas une base SQLite

iCloud Drive synchronise des fichiers entiers, sans rien savoir de leur contenu : une base
SQLite modifiée sur place (avec ses fichiers `-wal` et `-shm`) peut être corrompue par une
synchronisation au milieu d'une écriture ou par deux Mac qui l'écrivent, et toutes les séances
seraient perdues. Un fichier par séance, écrit d'un bloc, ne risque au pire qu'un conflit sur
une seule séance, et reste lisible par n'importe quel outil.

### Index local

Les totaux de chaque séance sont gardés dans un index, dans les caches de l'app
(`~/Library/Caches/com.arnrso.foulee/index.json`, jamais synchronisé : chaque Mac a le sien).
À l'ouverture des statistiques, seuls les fichiers nouveaux ou modifiés (date et taille) sont
décodés ; les relevés d'une séance ne sont lus qu'à l'ouverture de son détail. L'index peut être
supprimé sans risque : il est reconstruit à la lecture suivante.

## Publier une version

Pousser un tag `v…` sur `main` : GitHub Actions ([release.yml](.github/workflows/release.yml))
compile l'app, produit le `.zip` et le `.dmg` (signés ad hoc, non notarisés), signe la mise à
jour pour Sparkle, génère `appcast.xml` et crée la release avec les notes de
[Support/release-notes.md](Support/release-notes.md). Le numéro de build est celui de
l'exécution du workflow : il augmente tout seul.

```sh
git tag v0.3.0
git push origin v0.3.0
```

En local, `scripts/package.sh 0.3.0` produit les mêmes fichiers dans `dist/`.
L'icône et le fond du `.dmg` sont générés par `swift scripts/make-artwork.swift`.

### Signature des mises à jour (Sparkle)

Foulée vérifie chaque jour `appcast.xml`, publié avec chaque release. La CI signe le `.zip`
avec la clé privée EdDSA (secret `SPARKLE_PRIVATE_KEY`) ; l'app n'accepte que les mises à jour
signées par la clé correspondant à `SUPublicEDKey` ([Info.plist](Support/Info.plist)). Le
workflow échoue si l'appcast n'est pas signé.

La clé privée est aussi dans le trousseau du mainteneur (compte `foulee` de l'outil
`generate_keys` de Sparkle). La perdre empêche toute mise à jour des versions installées : la
conserver en lieu sûr.

## Pull requests

Une branche par changement, et une pull request vers `main`. Le modèle de PR rappelle les
vérifications : CI verte, test sur un vrai tapis si la connexion ou le pilotage sont concernés,
README ou notes de version à jour si le comportement visible change.

En contribuant, vous acceptez que votre code soit distribué sous licence
[GNU GPL 3.0](LICENSE).
