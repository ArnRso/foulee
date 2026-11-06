# Foulée

Pilote un tapis de marche Bluetooth depuis la barre des menus de macOS : vitesse, distance,
temps et énergie en direct, démarrage, pause, arrêt et réglage de la vitesse.

Repose sur le protocole standard FTMS (Fitness Machine Service, `0x1826`) via CoreBluetooth.
Validé sur un tapis à module FitShow (`FS-37FBED`) ; le protocole et les trames relevées sont
documentés dans le [POC Python](poc/README.md).

## Installer

Télécharger le `.dmg` de la [dernière release](https://github.com/ArnRso/foulee/releases/latest), l'ouvrir et
glisser Foulée dans Applications. L'app n'est pas notarisée : au premier lancement, macOS la bloque ;
l'autoriser dans Réglages Système › Confidentialité et sécurité › « Ouvrir quand même ».

Le tapis n'accepte qu'une connexion à la fois : fermer l'appli du fabricant sur le téléphone.

## Sécurité du pilotage

Quelqu'un marche sur le tapis : toute commande passe par des garde-fous.

- Chaque consigne de vitesse est arrondie au pas du tapis et bornée par sa plage (`0x2AD4`)
  et par la **vitesse maximale** choisie dans les Réglages (4 km/h par défaut). La télécommande
  du tapis n'est pas bornée.
- Quitter Foulée envoie Stop au tapis avant de se déconnecter.
- Une perte de connexion est signalée (icône ⚠︎ et bip si le tapis tournait) :
  **le tapis continue alors de tourner**, l'arrêter à la télécommande. Foulée se reconnecte seul.
- Après une pause, une reprise ou un arrêt, le tapis repart à sa vitesse minimale : la consigne
  précédente est oubliée, les boutons + et − repartent de la vitesse réelle.

## Pilotage

- **Démarrer / Pause / Reprendre / Arrêter**, sans confirmation.
- **+ et −** : changent la vitesse de l'incrément choisi (0,1 km/h par défaut, jamais plus fin
  que le pas du tapis).
- **Bascule lente** (tortue / lièvre) : passe à la vitesse lente (1 km/h par défaut), puis
  revient à la vitesse quittée. Si la vitesse a été changée entre-temps, la bascule ralentit à
  nouveau depuis la nouvelle vitesse.

### Réglages (⌘,)

Vitesse maximale, incrément des boutons, vitesse lente, raccourcis clavier, dossier des
séances, ouverture à la connexion et recherche automatique des mises à jour.

### Raccourcis clavier

Globaux (actifs dans toutes les apps), modifiables dans les Réglages, via
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (sans autorisation
d'accessibilité) :

| Action | Par défaut |
|---|---|
| Démarrer / pause | ⌃⌥ Espace |
| Accélérer | ⌃⌥ ↑ |
| Ralentir | ⌃⌥ ↓ |
| Bascule vitesse lente | ⌃⌥ L |
| Arrêter | ⌃⌥ S |

## Séances

Chaque séance est enregistrée dans un fichier JSON, par défaut dans **iCloud Drive › Foulee**
(ou Documents › Foulee si iCloud Drive est désactivé) ; le dossier se change depuis le menu.
Dossier et fichiers ont des noms ASCII sans espace (`session_2026-11-06_15-16-23.json`, heure
locale du début) ; les séances de l'ancien dossier `Foulée` y sont reprises au lancement.
Foulée n'est pas sandboxée : elle écrit directement dans le dossier iCloud Drive, sans conteneur
iCloud ni entitlement, ce qui reste compatible avec la signature ad hoc des releases.

- Une séance commence quand la bande se met à tourner (depuis Foulée ou la télécommande) et se
  termine quand le tapis signale un arrêt ou remet ses compteurs à zéro. Les pauses et les pertes
  de connexion ne la coupent pas.
- Le fichier contient les totaux (distance, temps de marche, énergie, vitesses moyenne et
  maximale) et un relevé par seconde. Il est sauvegardé toutes les 30 secondes pendant la marche.
- Format compact (version 3) : JSON sans indentation, relevés rangés en colonnes
  (`sampleColumns` : un tableau par mesure), environ 120 Ko par heure de marche. Les fichiers
  des versions précédentes sont relus, et réécrits au format compact à leur première lecture.

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
décodés ; les relevés d'une séance ne sont lus qu'à l'ouverture de son détail. L'index peut
être supprimé sans risque : il est reconstruit à la lecture suivante.
- Une séance interrompue par la fermeture de Foulée est enregistrée avec `isInterrupted`.
- Les séances de moins de 10 m et d'une minute ne sont pas conservées.
- Le fichier contient aussi les événements (démarrage, pause, arrêt, consignes de vitesse
  envoyées par Foulée, pertes de connexion). Les changements de vitesse faits à la télécommande
  ne sont pas signalés par le tapis : ils sont retrouvés dans les relevés.

### Statistiques

Menu › Statistiques… ouvre une fenêtre qui présente toutes les séances du dossier :

- **Vue d'ensemble** : totaux d'aujourd'hui, de la semaine, du mois et depuis le début ;
  histogramme par jour (30 derniers), semaine ou mois (12 derniers) de la distance, du temps,
  de l'énergie ou du nombre de séances ; tableau détaillé de chaque période.
- **Séance** : totaux, courbe de vitesse avec les événements, et chronologie heure par heure
  de chaque accélération et décélération (de combien à combien), pause, reprise et arrêt.
- **En cours** : la séance en cours apparaît en tête de liste et dans les totaux, mise à jour
  à chaque relevé du tapis (environ une fois par seconde) ; à l'arrêt, elle rejoint les séances
  enregistrées sans changer de vue.

## Publier une version

Pousser un tag `v…` : GitHub Actions ([release.yml](.github/workflows/release.yml)) compile l'app,
produit le `.zip` et le `.dmg` (signés ad hoc) et crée la release avec les notes de
[Support/release-notes.md](Support/release-notes.md).

```sh
git tag v0.1.0
git push origin v0.1.0
```

En local, `scripts/package.sh 0.1.0` produit les mêmes fichiers dans `dist/`.

### Mises à jour automatiques (Sparkle)

Foulée vérifie chaque jour `appcast.xml`, publié avec chaque release. La CI signe le `.zip` avec la clé
privée EdDSA (secret `SPARKLE_PRIVATE_KEY`) ; l'app n'accepte que les mises à jour signées par la clé
correspondant à `SUPublicEDKey` (Info.plist). Perdre la clé privée empêche toute mise à jour
des versions installées : la conserver en lieu sûr.
L'icône et le fond du `.dmg` sont générés par `swift scripts/make-artwork.swift`.

## Qualité du code

Règles les plus strictes, vérifiées par la CI ([ci.yml](.github/workflows/ci.yml)) sur chaque pull request :

- **Tests** : le protocole FTMS (décodage des trames, encodage des commandes, bornage de la vitesse,
  découpage en séances)
  vit dans le package local [FTMSKit](Packages/FTMSKit), testé avec Swift Testing sur des trames
  réelles du tapis, y compris sous Address Sanitizer : `scripts/test.sh`
- **Formatage et style** : `swift format` avec toutes les règles activées ([.swift-format](.swift-format)) :
  `scripts/lint.sh` pour vérifier, `scripts/lint.sh --fix` pour reformater
- **Compilation** : Swift 6 en concurrence stricte, sûreté mémoire explicite (`unsafe`),
  `ExistentialAny`, `InternalImportsByDefault`, `MemberImportVisibility`, avertissements bloquants
- **Dépendances** : Dependabot propose chaque semaine les mises à jour de Sparkle, KeyboardShortcuts et des actions GitHub

## Compiler et lancer

Avec Xcode : ouvrir `Foulee.xcodeproj` et lancer le schéma **Foulee** (⌘R).
Pour signer avec son Apple ID, choisir son équipe dans la cible Foulee → Signing & Capabilities.

En ligne de commande (Release, dans `build/Foulee.app`) :

```sh
./build.sh
open build/Foulee.app
```

Pour un usage quotidien, installer dans `/Applications` puis cocher « Ouvrir Foulée à la connexion »
dans le menu de Foulée :

```sh
./build.sh --install
open /Applications/Foulee.app
```

Au premier démarrage, macOS demande l'autorisation Bluetooth
(Réglages Système → Confidentialité et sécurité → Bluetooth).
Sans équipe choisie, `build.sh` signe en ad hoc et la demande peut revenir après chaque compilation ; pour la réinitialiser :

```sh
tccutil reset BluetoothAlways com.arnrso.foulee
```

Journaux : `log stream --predicate 'subsystem == "com.arnrso.foulee"'`

## Licence

Foulée est distribué sous licence [GNU GPL 3.0](LICENSE) : vous pouvez l'utiliser, l'étudier, le modifier
et le redistribuer, à condition que toute version distribuée reste sous GPL 3.0 avec son code source.

Composants tiers : [Sparkle](https://sparkle-project.org) (licences MIT, BSD et zlib) et
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (licence MIT), reproduites dans
[Foulee/Legal/ThirdPartyNotices.txt](Foulee/Legal/ThirdPartyNotices.txt)). La licence de Foulée et celles des
composants tiers sont incluses dans l'app (`Foulee.app/Contents/Resources`).
