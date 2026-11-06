# POC Python

Toutes les commandes ci-dessous se lancent depuis ce dossier `poc/`.

POC Python de pilotage d'un tapis de marche FitShow (`FS-37FBED`) en Bluetooth
Low Energy via le protocole standard FTMS (Fitness Machine Service, `0x1826`).

## Prérequis

- macOS, Python 3.10+.
- **Autorisation Bluetooth du terminal** : Réglages Système > Confidentialité et
  sécurité > Bluetooth, activer l'application qui lance le script (Terminal, iTerm,
  VS Code…). Sans elle, le scan ne trouve rien ou le process est tué sans message.
  Au premier lancement, macOS peut afficher une demande d'autorisation.
- **Fermer l'appli FitShow sur l'iPhone** : le tapis n'accepte qu'une connexion à la fois.

## Installation

```bash
python3 -m venv .venv
```

```bash
.venv/bin/pip install -r requirements.txt
```

## Utilisation

Piloter le tapis (lecture des capacités, prise de contrôle, ligne d'état temps réel) :

```bash
.venv/bin/python tapis.py
```

Commandes : `start` (avec confirmation), `stop`, `pause`, `+` / `-` (±0,5 km/h),
`v 3.5` (vitesse cible), `controle` (redemander le contrôle), `aide`, `q`.

Sécurités :
- plafond de vitesse de 4 km/h par défaut, modifiable avec `--vitesse-max 5` ;
  toute consigne est aussi bornée par la plage annoncée par le tapis (`0x2AD4`) ;
- confirmation avant `start` ;
- `q` ou Ctrl+C envoient Stop avant de se déconnecter ;
- une perte de connexion est signalée : **le tapis continue alors de tourner**.

Lister tous les appareils BLE visibles (diagnostic) :

```bash
.venv/bin/python tapis.py --scan
```

Explorer le tapis (services, caractéristiques, valeurs lisibles, puis écoute de
toutes les notifications en brut jusqu'à Ctrl+C) :

```bash
.venv/bin/python tapis.py --explore
```

Sous macOS, bleak identifie les appareils par un UUID propre au Mac (pas l'adresse
MAC). Une fois connu (affiché au scan), on peut le passer directement :

```bash
.venv/bin/python tapis.py --explore --adresse XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

## Logs

Les fichiers sont écrits dans `logs/` avec un nom horodaté :
- `session_*.csv` : chaque trame `0x2ACD` (brut hex + valeurs décodées) ;
- `commandes_*.txt` : commandes envoyées, réponses du Control Point, statuts du tapis ;
- `explore_*.txt` : sortie du mode exploration.

## Ce qu'on sait du tapis

- Trame `0x2ACD` de 19 octets, conforme à la norme FTMS (décodée selon les flags).
- Vitesse de 1,00 à 12,00 km/h par pas de 0,10.
- Pilotage FTMS standard accepté (Request Control, Start, Stop, Pause, vitesse cible) ;
  le tapis suit une nouvelle consigne en 1 à 2 s.
- Start et reprise après pause repartent à 1,0 km/h ; la pause conserve distance et
  temps, le stop les remet à zéro.
- `0x2ADA` et `0x2AD3` ne notifient qu'aux changements d'état (start, pause, stop),
  pas aux changements de vitesse.
- Pas d'inclinaison motorisée (pieds réglables à la main) : les champs
  inclinaison/rampe valent toujours 0 malgré le flag.

## Structure

- `ble.py` : scan, connexion, UUID, mode exploration.
- `decodage.py` : décodage des trames FTMS (Treadmill Data décodé selon les flags).
- `tapis.py` : point d'entrée en ligne de commande.

## Avancement

1. Scan + connexion + `--explore` ✔
2. Décodage de `0x2ACD` (Treadmill Data) + log CSV ✔
3. Lecture de `0x2ACC` / `0x2AD4` / `0x2AD5` ✔
4. Request Control + Start/Stop/Pause ✔
5. Changement de vitesse ✔
