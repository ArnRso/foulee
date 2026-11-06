"""Point d'entrée : pilotage d'un tapis de marche FTMS en Bluetooth.

Exemples :
    python tapis.py                      # connexion, pilotage, affichage temps réel et logs
    python tapis.py --vitesse-max 5      # relever le plafond de vitesse (4 km/h par défaut)
    python tapis.py --scan               # liste tous les appareils BLE visibles
    python tapis.py --explore            # services, caractéristiques et trames brutes
    python tapis.py --adresse <UUID macOS du tapis>
"""

import argparse
import asyncio
import csv
import sys
from datetime import datetime
from pathlib import Path

from bleak import BleakClient
from bleak.backends.characteristic import BleakGATTCharacteristic

import ble
import decodage

DOSSIER_LOGS = Path(__file__).parent / "logs"

COLONNES_CSV = ["timestamp", "trame_hex", "vitesse_kmh", "distance_m", "temps_s", "kcal",
                "inclinaison_pct", "rampe_deg", "octets_7_11_hex", "ecart_longueur"]

# Pas minimal des commandes + et -
PAS_CLAVIER = 0.5

AIDE = ("Commandes : start | stop | pause | + | - | v 3.5 | controle | aide | q")


def lire_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Pilotage d'un tapis de marche FTMS (POC)")
    parser.add_argument("--scan", action="store_true",
                        help="lister tous les appareils BLE visibles puis quitter")
    parser.add_argument("--explore", action="store_true",
                        help="lister services/caractéristiques et logger tout ce qui notifie")
    parser.add_argument("--adresse",
                        help="identifiant macOS (UUID) du tapis, pour éviter la recherche par nom")
    parser.add_argument("--timeout", type=float, default=10.0,
                        help="durée max du scan en secondes (défaut : 10)")
    parser.add_argument("--vitesse-max", type=float, default=4.0,
                        help="plafond de vitesse en km/h, en plus des bornes du tapis (défaut : 4)")
    return parser.parse_args()


class Console:
    """Affichage en bas du terminal : une ligne d'état rafraîchie juste au-dessus
    de l'invite « > ». Les messages s'insèrent au-dessus de la ligne d'état."""

    def __init__(self) -> None:
        self.etat = "En attente des données du tapis…"

    def ouvrir(self) -> None:
        print(f"{self.etat}\n> ", end="", flush=True)

    def maj_etat(self, ligne: str) -> None:
        self.etat = ligne
        # Sauver le curseur, remonter sur la ligne d'état, la réécrire, revenir
        print(f"\x1b7\x1b[1A\r\x1b[2K{ligne}\x1b8", end="", flush=True)

    def message(self, texte: str) -> None:
        # Effacer l'invite et la ligne d'état, écrire le message, puis les réafficher
        print(f"\r\x1b[2K\x1b[1A\r\x1b[2K{texte}\n{self.etat}\n> ", end="", flush=True)

    def apres_saisie(self, saisie: str) -> None:
        # La touche Entrée a fait descendre le curseur : on efface la ligne tapée
        # et on la remet dans l'historique des messages
        print("\x1b[1A\r\x1b[2K", end="", flush=True)
        self.message(f"> {saisie}")


class Pilote:
    """Session de pilotage : données temps réel, commandes clavier et sécurités."""

    def __init__(self, client: BleakClient, vitesse_max: float):
        self.client = client
        self.console = Console()
        self.plafond = vitesse_max
        self.vitesse_min = 0.0
        self.vitesse_max = vitesse_max
        self.pas_tapis = 0.1
        self.vitesse_actuelle: float | None = None
        self.vitesse_cible: float | None = None
        self.controle = False
        self.saisies: asyncio.Queue[str] = asyncio.Queue()

        DOSSIER_LOGS.mkdir(exist_ok=True)
        horodatage = f"{datetime.now():%Y%m%d_%H%M%S}"
        self.chemin_csv = DOSSIER_LOGS / f"session_{horodatage}.csv"
        self.chemin_journal = DOSSIER_LOGS / f"commandes_{horodatage}.txt"
        self.fichier_csv = self.chemin_csv.open("w", newline="", encoding="utf-8")
        self.csv = csv.writer(self.fichier_csv)
        self.csv.writerow(COLONNES_CSV)
        self.fichier_journal = self.chemin_journal.open("w", encoding="utf-8")
        self.point_controle = ble.PointDeControle(client, self.journal)

    def journal(self, texte: str) -> None:
        """Affiche un message et l'écrit dans le journal des commandes."""
        self.fichier_journal.write(f"{datetime.now().isoformat(timespec='milliseconds')}  {texte}\n")
        self.fichier_journal.flush()
        self.console.message(texte)

    # --- Lectures au démarrage ---------------------------------------------------

    async def lire_caracteristiques(self) -> None:
        mesures, reglages = decodage.decoder_fonctions(
            await self.client.read_gatt_char(ble.FTMS_FEATURE))
        print(f"Mesures fournies : {', '.join(mesures)}")
        print(f"Réglages acceptés : {', '.join(reglages)}")

        vmin, vmax, pas = decodage.decoder_plage_vitesse(
            await self.client.read_gatt_char(ble.SPEED_RANGE))
        print(f"Plage de vitesse du tapis : {vmin:.2f} à {vmax:.2f} km/h, pas {pas:.2f}")
        self.vitesse_min = vmin
        self.vitesse_max = min(vmax, self.plafond)
        self.pas_tapis = pas
        print(f"Plafond de sécurité : {self.vitesse_max:.2f} km/h")

        if self.client.services.get_characteristic(ble.INCLINATION_RANGE) is None:
            print("Plage d'inclinaison (0x2AD5) : absente")
        else:
            brut = await self.client.read_gatt_char(ble.INCLINATION_RANGE)
            print(f"Plage d'inclinaison (0x2AD5) : {brut.hex(' ')}")

    # --- Notifications du tapis --------------------------------------------------

    def recu_donnees(self, _car: BleakGATTCharacteristic, data: bytearray) -> None:
        d = decodage.decoder_treadmill_data(bytes(data))
        self.vitesse_actuelle = d.vitesse_kmh
        self.csv.writerow([
            datetime.now().isoformat(timespec="milliseconds"),
            data.hex(),
            d.vitesse_kmh, d.distance_m, d.temps_s, d.kcal,
            d.inclinaison_pct, d.rampe_deg,
            # Zone inclinaison/rampe gardée en brut pour vérifier le décodage
            data[7:12].hex(" "),
            d.ecart_longueur,
        ])
        self.fichier_csv.flush()
        cible = "--" if self.vitesse_cible is None else f"{self.vitesse_cible:.2f}"
        controle = "oui" if self.controle else "NON"
        self.console.maj_etat(f"{decodage.ligne_etat(d)} | cible {cible} | contrôle {controle}")

    def recu_statut(self, _car: BleakGATTCharacteristic, data: bytearray) -> None:
        self.journal(f"Statut tapis : {decodage.decrire_statut(bytes(data))}  [{data.hex(' ')}]")
        if data[0] == 0x05 and len(data) >= 3:
            self.vitesse_cible = int.from_bytes(data[1:3], "little") / 100
        # Après arrêt, pause ou reprise, le tapis repart à sa vitesse minimale :
        # l'ancienne cible ne doit plus servir de base aux commandes + et -
        if data[0] in (0x02, 0x04):
            self.vitesse_cible = None
        if data[0] == 0xFF:
            self.controle = False

    def recu_entrainement(self, _car: BleakGATTCharacteristic, data: bytearray) -> None:
        self.journal(f"État entraînement : {decodage.decrire_etat_entrainement(bytes(data))}"
                     f"  [{data.hex(' ')}]")

    # --- Commandes ---------------------------------------------------------------

    def _afficher_resultat(self, resultat: int | None) -> None:
        if resultat in (0x02, 0x05) or resultat is None:
            self.journal("   → le Control Point ne coopère pas : piste FFF0 (plan B) à étudier")

    async def demander_controle(self) -> None:
        resultat = await self.point_controle.demander_controle()
        self.controle = resultat == 0x01
        self._afficher_resultat(resultat)

    async def regler_vitesse(self, kmh: float) -> None:
        # Arrondi au pas du tapis puis bornage entre le minimum du tapis et le plafond
        kmh = round(round(kmh / self.pas_tapis) * self.pas_tapis, 2)
        if kmh > self.vitesse_max:
            self.journal(f"   {kmh:.2f} km/h dépasse le plafond, ramené à {self.vitesse_max:.2f}")
            kmh = self.vitesse_max
        if kmh < self.vitesse_min:
            self.journal(f"   {kmh:.2f} km/h sous le minimum du tapis, ramené à "
                         f"{self.vitesse_min:.2f} (utiliser stop pour arrêter)")
            kmh = self.vitesse_min
        resultat = await self.point_controle.vitesse(kmh)
        if resultat == 0x01:
            self.vitesse_cible = kmh
        self._afficher_resultat(resultat)

    async def ajuster_vitesse(self, sens: int) -> None:
        pas = max(PAS_CLAVIER, self.pas_tapis)
        base = self.vitesse_cible or self.vitesse_actuelle or self.vitesse_min
        await self.regler_vitesse(base + sens * pas)

    async def demarrer(self) -> None:
        self.console.message("Démarrer le tapis ? Quelqu'un doit être prêt dessus. "
                             "Taper « oui » pour confirmer :")
        reponse = await self.lire_saisie()
        if reponse is None or reponse.lower() not in ("oui", "o"):
            self.journal("Démarrage annulé.")
            return
        self._afficher_resultat(await self.point_controle.demarrer())

    async def executer(self, saisie: str) -> bool:
        """Exécute une commande clavier. Renvoie False pour quitter."""
        mots = saisie.split()
        if not mots:
            return True
        # « v6 » est accepté comme « v 6 »
        if len(mots) == 1 and len(mots[0]) > 1 and mots[0][0].lower() == "v":
            mots = ["v", mots[0][1:]]
        commande = mots[0].lower()
        if commande in ("q", "quit", "quitter"):
            return False
        if commande in ("aide", "?", "h"):
            self.console.message(AIDE)
            return True
        if commande == "controle":
            await self.demander_controle()
            return True
        if not self.controle:
            self.console.message("Contrôle non obtenu : taper « controle » pour le redemander.")
            return True
        if commande == "start":
            await self.demarrer()
        elif commande == "stop":
            self._afficher_resultat(await self.point_controle.arreter())
        elif commande == "pause":
            self._afficher_resultat(await self.point_controle.pause())
        elif commande == "+":
            await self.ajuster_vitesse(+1)
        elif commande == "-":
            await self.ajuster_vitesse(-1)
        elif commande == "v" and len(mots) == 2:
            try:
                kmh = float(mots[1].replace(",", "."))
            except ValueError:
                self.console.message(f"Vitesse illisible : {mots[1]}")
                return True
            await self.regler_vitesse(kmh)
        else:
            self.console.message(f"Commande inconnue. {AIDE}")
        return True

    # --- Boucle principale -------------------------------------------------------

    async def lire_saisie(self) -> str | None:
        """Attend une ligne au clavier. None si la connexion est perdue ou stdin fermé."""
        while self.client.is_connected:
            try:
                ligne = await asyncio.wait_for(self.saisies.get(), 0.5)
            except TimeoutError:
                continue
            if not ligne:
                return None
            saisie = ligne.strip()
            self.console.apres_saisie(saisie)
            return saisie
        return None

    async def lancer(self) -> None:
        await self.lire_caracteristiques()
        print(f"Log CSV : {self.chemin_csv}")
        print(f"Journal des commandes : {self.chemin_journal}")
        print(AIDE + "\n")
        self.console.ouvrir()

        await self.client.start_notify(ble.MACHINE_STATUS, self.recu_statut)
        await self.client.start_notify(ble.TRAINING_STATUS, self.recu_entrainement)
        await self.point_controle.activer()
        await self.demander_controle()
        await self.client.start_notify(ble.TREADMILL_DATA, self.recu_donnees)

        boucle = asyncio.get_running_loop()
        boucle.add_reader(sys.stdin, lambda: self.saisies.put_nowait(sys.stdin.readline()))
        try:
            while (saisie := await self.lire_saisie()) is not None:
                if not await self.executer(saisie):
                    break
        finally:
            boucle.remove_reader(sys.stdin)
            await self.fermer()

    async def fermer(self) -> None:
        """Sécurité : Stop avant de se déconnecter (sur q, Ctrl+C ou erreur)."""
        if self.controle and self.client.is_connected:
            self.journal("Arrêt du tapis avant déconnexion…")
            await self.point_controle.arreter()
        # Plus aucune notification ne doit écrire dans les fichiers une fois fermés
        if self.client.is_connected:
            for uuid in (ble.TREADMILL_DATA, ble.MACHINE_STATUS, ble.TRAINING_STATUS,
                         ble.CONTROL_POINT):
                await self.client.stop_notify(uuid)
        print()
        self.fichier_csv.close()
        self.fichier_journal.close()


async def principal(args: argparse.Namespace) -> None:
    if args.scan:
        await ble.lister_appareils(args.timeout)
        return

    cible = args.adresse or await ble.trouver_tapis(args.timeout)
    if cible is None:
        return

    print("Connexion…")
    async with ble.creer_client(cible) as client:
        print("Connecté.")
        try:
            if args.explore:
                await ble.explorer(client, DOSSIER_LOGS)
            else:
                await Pilote(client, args.vitesse_max).lancer()
        finally:
            ble.deconnexion_volontaire()


def main() -> None:
    args = lire_arguments()
    try:
        asyncio.run(principal(args))
    except KeyboardInterrupt:
        print("\nArrêt demandé.")


if __name__ == "__main__":
    main()
