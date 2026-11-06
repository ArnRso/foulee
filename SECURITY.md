# Sécurité

## Signaler une vulnérabilité

Merci de **ne pas ouvrir d'issue publique** pour une faille de sécurité. Utilisez le
[signalement privé de GitHub](https://github.com/ArnRso/foulee/security/advisories/new) :
seul le mainteneur voit le rapport, et un correctif peut être publié avant toute divulgation.

Précisez la version de Foulée (menu › « À propos de Foulée x.y.z »), la version de macOS, le
modèle de tapis et, si possible, les étapes pour reproduire le problème.

## Versions prises en charge

Seule la dernière version publiée reçoit des correctifs : les versions installées se mettent
à jour automatiquement (Sparkle).

## Points sensibles

- **Pilotage d'un appareil physique** : Foulée commande la vitesse d'un tapis sur lequel
  quelqu'un marche. Toute consigne est bornée par la plage annoncée par le tapis et par un
  plafond choisi par l'utilisateur ; le démarrage demande une confirmation ; Stop est envoyé
  à la fermeture de l'app. Un contournement de ces garde-fous est une faille de sécurité.
- **Bluetooth** : Foulée ne se connecte qu'aux appareils annonçant le service Fitness Machine
  (`0x1826`). Aucune donnée n'est envoyée sur le réseau.
- **Mises à jour** : chaque mise à jour est signée (EdDSA) ; l'app refuse toute archive dont la
  signature ne correspond pas à la clé publique intégrée (`SUPublicEDKey`).
