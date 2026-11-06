# Foulée

**Pilotez votre tapis de marche depuis la barre des menus de votre Mac.**

Foulée se connecte en Bluetooth à votre tapis de marche : vous voyez votre vitesse, votre
distance, votre temps et vos calories en direct, vous démarrez, mettez en pause et changez de
vitesse d'un clic ou d'un raccourci clavier, sans quitter ce que vous faites. Chaque séance est
enregistrée, et une fenêtre de statistiques retrace vos journées, vos semaines et vos mois de
marche.

Idéal pour un tapis sous un bureau assis-debout : vous marchez, vous travaillez, Foulée reste
discrète dans la barre des menus.

[**Télécharger la dernière version**](https://github.com/ArnRso/foulee/releases/latest)
· macOS 15 ou plus récent · Mac Apple Silicon ou Intel · Gratuit et open source

## Ce que fait Foulée

- **En direct** : vitesse, distance, temps de marche et énergie dépensée, dans un menu qui
  s'ouvre d'un clic. La vitesse s'affiche aussi à côté de l'icône pendant que vous marchez.
- **Pilotage** : démarrer, mettre en pause, reprendre, arrêter, accélérer ou ralentir au
  dixième de km/h près.
- **Ralentir d'un geste** : un bouton passe le tapis à vitesse lente (pour un appel, une
  réunion…), puis le ramène à votre vitesse d'avant.
- **Raccourcis clavier** : toutes les commandes sont accessibles depuis n'importe quelle app,
  et les raccourcis se changent dans les Réglages.
- **Séances enregistrées** : chaque séance est gardée, seconde par seconde, dans un dossier
  iCloud Drive, donc sauvegardée et retrouvée sur vos autres Mac.
- **Statistiques** : totaux du jour, de la semaine, du mois et depuis le début, histogrammes,
  et pour chaque séance la courbe de vitesse et l'heure de chaque accélération, pause ou reprise.
- **Garde-fous** : une vitesse maximale que Foulée ne dépasse jamais, et l'arrêt du tapis quand
  vous quittez l'app.
- **Mises à jour automatiques** : Foulée vous propose les nouvelles versions d'elle-même.

## Tapis compatibles

Foulée fonctionne avec les tapis qui parlent le protocole Bluetooth standard des appareils de
fitness, **FTMS** (Fitness Machine Service). C'est le cas de nombreux tapis récents, notamment
ceux équipés d'un module FitShow, dont le nom Bluetooth commence par `FS-`.

Indices que votre tapis est compatible : il se connecte à des applis comme Zwift ou Kinomap, ou
sa fiche technique mentionne « FTMS ». En cas de doute, essayez : si Foulée trouve votre tapis
et affiche sa vitesse, c'est bon signe.

Foulée a été mise au point sur un tapis de marche à module FitShow. Les tapis à inclinaison
motorisée sont reconnus, mais Foulée ne pilote pas encore l'inclinaison.

## Installer

1. Téléchargez **`Foulee-….dmg`** depuis la
   [dernière version](https://github.com/ArnRso/foulee/releases/latest), ouvrez-le et glissez
   **Foulée** dans le dossier **Applications**.
2. Lancez Foulée. Elle n'est pas notarisée par Apple : la première fois, macOS refuse de
   l'ouvrir. Allez dans **Réglages Système › Confidentialité et sécurité** et cliquez sur
   **Ouvrir quand même**. Ou, dans le Terminal :

   ```sh
   xattr -dr com.apple.quarantine /Applications/Foulee.app
   ```

3. Acceptez l'**autorisation Bluetooth** que demande macOS.

## Premiers pas

1. **Allumez le tapis** et **fermez l'appli du fabricant** sur votre téléphone (ou coupez le
   Bluetooth du téléphone) : un tapis n'accepte qu'une connexion à la fois.
2. Cliquez sur l'icône de marcheur dans la barre des menus. Foulée cherche le tapis, s'y
   connecte et en prend le contrôle : son nom s'affiche avec un point vert.
3. Cliquez sur **Démarrer**. Le tapis part à sa vitesse minimale ; réglez-la avec **+** et **−**.

La première fois, ouvrez aussi les **Réglages** (menu › Réglages…) pour choisir votre vitesse
maximale.

## Utilisation

### Le menu

| Bouton | Effet |
|---|---|
| **Démarrer** / **Reprendre** | Lance le tapis, ou le relance après une pause. |
| **Pause** | Arrête la bande en gardant la distance et le temps de la séance. |
| **Arrêter** | Termine la séance : le tapis remet ses compteurs à zéro. |
| **−** / **+** | Ralentit ou accélère (de 0,1 km/h par défaut). |
| 🐢 **1,0 km/h** | Passe à la vitesse lente. Le bouton devient 🐇 et affiche votre vitesse d'avant : un clic vous y ramène. |

Après une pause ou un arrêt, le tapis repart toujours à sa vitesse minimale.

### Raccourcis clavier

Ils fonctionnent dans toutes les apps, même quand le menu de Foulée est fermé :

| Action | Raccourci par défaut |
|---|---|
| Démarrer / pause | ⌃⌥ Espace |
| Accélérer | ⌃⌥ ↑ |
| Ralentir | ⌃⌥ ↓ |
| Vitesse lente / vitesse d'avant | ⌃⌥ L |
| Arrêter | ⌃⌥ S |

(⌃ = Contrôle, ⌥ = Option.) Changez-les dans les Réglages. Si Foulée n'est pas connectée au
tapis, un raccourci émet simplement un bip.

### Réglages

Menu › **Réglages…** :

- **Vitesse maximale** : Foulée ne demande jamais plus au tapis (4 km/h au départ).
- **Incrément** des boutons + et − : 0,1, 0,2, 0,5 ou 1 km/h.
- **Vitesse lente** du bouton tortue (1 km/h au départ).
- **Raccourcis clavier**.
- **Dossier des séances**.
- **Ouvrir Foulée à la connexion** au Mac, et recherche automatique des mises à jour.

## Votre sécurité

Quelqu'un marche sur le tapis : Foulée est prudente.

- Toute vitesse demandée par Foulée (boutons, raccourcis, vitesse lente) est limitée à votre
  **vitesse maximale** et à la plage du tapis. La télécommande du tapis, elle, n'est pas
  limitée par Foulée.
- **Quitter Foulée arrête le tapis.**
- Si la **connexion Bluetooth est perdue**, l'icône devient ⚠︎ et le Mac émet un bip : **le tapis
  continue alors de tourner à sa dernière vitesse**. Arrêtez-le à la télécommande ou avec le
  bouton du tapis. Foulée se reconnecte toute seule dès que possible.
- Gardez toujours la clé de sécurité du tapis accrochée à vous.

## Séances et statistiques

### Où sont vos séances

Chaque séance est enregistrée dans **iCloud Drive › Foulee** (ou Documents › Foulee si iCloud
Drive est désactivé), un fichier par séance, nommé d'après sa date :
`session_2026-11-06_15-16-23.json`. Changez de dossier dans les Réglages.

- Une séance commence quand la bande se met à tourner, que ce soit depuis Foulée ou depuis la
  télécommande, et se termine à l'arrêt du tapis. Les pauses ne la coupent pas.
- Elle est sauvegardée toutes les 30 secondes : un plantage ne vous fait pas perdre votre marche.
- Les séances de moins d'une minute et de moins de 10 mètres ne sont pas gardées.
- Les fichiers sont au format JSON, lisibles par d'autres outils si vous voulez exploiter vos
  données vous-même.

### La fenêtre Statistiques

Menu › **Statistiques…** :

- **Vue d'ensemble** : totaux d'aujourd'hui, de la semaine, du mois et depuis le début ;
  histogramme des 30 derniers jours, des 12 dernières semaines ou des 12 derniers mois, en
  distance, temps, énergie ou nombre de séances ; tableau détaillé par période.
- **Une séance** : distance, temps de marche, énergie, vitesses moyenne et maximale, courbe de
  vitesse, et chronologie de chaque accélération (« 2,0 → 2,5 km/h à 15 h 16 »), pause, reprise
  et arrêt, y compris ceux faits à la télécommande.
- **Séance en cours** : elle apparaît en tête de liste et se met à jour en direct.

### Vos données

Foulée ne collecte rien et n'envoie rien : vos séances restent dans votre dossier. La seule
connexion à Internet est la vérification quotidienne des mises à jour, sur GitHub.

## Mises à jour

Foulée vérifie chaque jour s'il existe une nouvelle version et vous la propose dans son menu.
Vous pouvez aussi vérifier à la main : menu › **Rechercher les mises à jour…**. Chaque mise à
jour est signée : Foulée refuse toute version qui ne vient pas de ce projet.

Après une mise à jour, macOS peut redemander l'autorisation Bluetooth.

## En cas de problème

**Foulée ne trouve pas le tapis**
- Vérifiez que l'appli du fabricant est fermée sur votre téléphone, ou coupez le Bluetooth du
  téléphone : le tapis ne s'annonce plus quand un appareil y est déjà connecté.
- Réveillez le tapis (télécommande ou bouton) : certains se mettent en veille.
- Vérifiez que le Bluetooth du Mac est activé.

**« Bluetooth indisponible »**
Autorisez Foulée dans **Réglages Système › Confidentialité et sécurité › Bluetooth**. Si la
demande ne réapparaît pas :

```sh
tccutil reset BluetoothAlways com.arnrso.foulee
```

**Le tapis refuse le contrôle (point orange)**
Une autre appli est probablement connectée au tapis : fermez-la, puis cliquez sur **Prendre le
contrôle du tapis** dans le menu.

**Autre chose**
Menu › **Diagnostic…** affiche ce que le tapis annonce et le journal des échanges. Le bouton
**Copier le diagnostic** le met dans le presse-papiers, prêt à joindre à un signalement.

## Signaler un problème, proposer une idée

[Ouvrez une issue](https://github.com/ArnRso/foulee/issues/new/choose) en indiquant la version de
Foulée, celle de macOS, votre modèle de tapis, et en collant le diagnostic. Pour une faille de
sécurité, utilisez plutôt le [signalement privé](SECURITY.md).

Envie de contribuer au code ? Tout est expliqué dans [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

Foulée est un logiciel libre, sous licence [GNU GPL 3.0](LICENSE) : vous pouvez l'utiliser,
l'étudier, le modifier et le redistribuer, à condition que toute version distribuée reste sous
GPL 3.0 avec son code source.

Foulée utilise [Sparkle](https://sparkle-project.org) pour ses mises à jour et
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) pour ses raccourcis
clavier ; leurs licences sont reproduites dans
[ThirdPartyNotices.txt](Foulee/Legal/ThirdPartyNotices.txt) et incluses dans l'app.
