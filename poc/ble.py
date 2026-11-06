"""Couche Bluetooth Low Energy : scan, connexion et exploration du tapis.

Repose sur bleak (CoreBluetooth sous macOS). Sous macOS, les appareils sont
identifiés par un UUID propre à ce Mac, pas par une adresse MAC.
"""

import asyncio
from collections.abc import Callable
from datetime import datetime
from pathlib import Path

from bleak import BleakClient, BleakScanner
from bleak.backends.characteristic import BleakGATTCharacteristic
from bleak.backends.device import BLEDevice
from bleak.backends.scanner import AdvertisementData

import decodage


def uuid16(court: int) -> str:
    """Convertit un UUID 16 bits (ex. 0x1826) en UUID 128 bits complet."""
    return f"0000{court:04x}-0000-1000-8000-00805f9b34fb"


# Services
FTMS_SERVICE = uuid16(0x1826)
FITSHOW_SERVICE = uuid16(0xFFF0)

# Caractéristiques FTMS
FTMS_FEATURE = uuid16(0x2ACC)
TREADMILL_DATA = uuid16(0x2ACD)
SPEED_RANGE = uuid16(0x2AD4)
INCLINATION_RANGE = uuid16(0x2AD5)
CONTROL_POINT = uuid16(0x2AD9)
MACHINE_STATUS = uuid16(0x2ADA)
TRAINING_STATUS = uuid16(0x2AD3)

PREFIXE_NOM = "FS-"


def nom_court(uuid: str) -> str:
    """Affiche un UUID standard Bluetooth sous sa forme courte (ex. 0x2ACD)."""
    if uuid.endswith("-0000-1000-8000-00805f9b34fb") and uuid.startswith("0000"):
        return f"0x{uuid[4:8].upper()}"
    return uuid


def est_le_tapis(device: BLEDevice, adv: AdvertisementData) -> bool:
    """Reconnaît le tapis : nom commençant par FS- ou service 1826 annoncé."""
    nom = adv.local_name or device.name or ""
    return nom.startswith(PREFIXE_NOM) or FTMS_SERVICE in adv.service_uuids


async def trouver_tapis(timeout: float = 10.0) -> BLEDevice | None:
    """Scanne les appareils BLE et renvoie le premier qui ressemble au tapis."""
    print(f"Scan Bluetooth ({timeout:.0f} s max)…")
    device = await BleakScanner.find_device_by_filter(est_le_tapis, timeout=timeout)
    if device is None:
        print("Aucun tapis trouvé. L'appli FitShow de l'iPhone est-elle bien fermée ?")
    else:
        print(f"Tapis trouvé : {device.name}  (identifiant macOS : {device.address})")
    return device


async def lister_appareils(timeout: float = 8.0) -> None:
    """Affiche tous les appareils BLE visibles, utile pour diagnostiquer un scan raté."""
    print(f"Scan de tous les appareils BLE ({timeout:.0f} s)…")
    resultats = await BleakScanner.discover(timeout=timeout, return_adv=True)
    for device, adv in sorted(resultats.values(), key=lambda r: -r[1].rssi):
        marque = "  <== tapis ?" if est_le_tapis(device, adv) else ""
        services = ", ".join(nom_court(u) for u in adv.service_uuids)
        print(f"  {adv.rssi:4d} dBm  {device.address}  {adv.local_name or device.name or '?'}"
              f"  [{services}]{marque}")


_deconnexion_volontaire = False


def deconnexion_volontaire() -> None:
    """À appeler avant de se déconnecter soi-même, pour ne pas déclencher l'alerte."""
    global _deconnexion_volontaire
    _deconnexion_volontaire = True


def creer_client(device: BLEDevice | str) -> BleakClient:
    """Crée le client BLE avec un callback qui signale clairement une déconnexion."""

    def deconnecte(_client: BleakClient) -> None:
        if _deconnexion_volontaire:
            print("Déconnecté proprement.")
            return
        print("\n" + "!" * 60)
        print("!!! CONNEXION PERDUE AVEC LE TAPIS !!!")
        print("!!! Le tapis continue peut-être de tourner : arrêtez-le à la main.")
        print("!" * 60, flush=True)

    return BleakClient(device, disconnected_callback=deconnecte)


def proprietes(car: BleakGATTCharacteristic) -> str:
    return ", ".join(car.properties)


async def explorer(client: BleakClient, dossier_logs: Path) -> None:
    """Mode --explore : liste services et caractéristiques, lit ce qui est lisible,
    s'abonne à tout ce qui notifie/indique et logue le brut jusqu'à Ctrl+C."""
    dossier_logs.mkdir(exist_ok=True)
    chemin = dossier_logs / f"explore_{datetime.now():%Y%m%d_%H%M%S}.txt"
    fichier = chemin.open("w", encoding="utf-8")

    def log(ligne: str) -> None:
        print(ligne)
        fichier.write(ligne + "\n")
        fichier.flush()

    log(f"Appareil : {client.name}  ({client.address})")
    log(f"MTU : {client.mtu_size}")
    a_notifier = []
    for service in client.services:
        log(f"\nService {nom_court(service.uuid)}  {service.description}")
        for car in service.characteristics:
            log(f"  Car. {nom_court(car.uuid)}  handle={car.handle}  [{proprietes(car)}]"
                f"  {car.description}")
            if "read" in car.properties:
                try:
                    valeur = await client.read_gatt_char(car)
                    log(f"      valeur lue : {valeur.hex(' ')}")
                except Exception as e:
                    log(f"      lecture impossible : {e}")
            for desc in car.descriptors:
                log(f"      Desc. {nom_court(desc.uuid)}  handle={desc.handle}")
            if "notify" in car.properties or "indicate" in car.properties:
                a_notifier.append(car)

    def recu(car: BleakGATTCharacteristic, data: bytearray) -> None:
        horodatage = datetime.now().isoformat(timespec="milliseconds")
        log(f"{horodatage}  {nom_court(car.uuid)}  ({len(data):2d} o)  {data.hex(' ')}")

    log("")
    for car in a_notifier:
        try:
            await client.start_notify(car, recu)
            log(f"Abonné à {nom_court(car.uuid)}")
        except Exception as e:
            log(f"Abonnement impossible à {nom_court(car.uuid)} : {e}")

    log(f"\nÉcoute en cours, log dans {chemin}. Ctrl+C pour arrêter.\n")
    try:
        while client.is_connected:
            await asyncio.sleep(0.5)
    finally:
        fichier.close()


class PointDeControle:
    """Commandes FTMS sur 0x2AD9 : écriture avec accusé, puis attente de l'indication
    de réponse « 80 <opcode> <résultat> »."""

    def __init__(self, client: BleakClient, journal: Callable[[str], None]):
        self.client = client
        self.journal = journal
        self._attente: asyncio.Future[bytes] | None = None
        self._opcode_attendu: int | None = None

    async def activer(self) -> None:
        """S'abonner aux indications : obligatoire AVANT toute écriture."""
        await self.client.start_notify(CONTROL_POINT, self._reponse)

    def _reponse(self, _car: BleakGATTCharacteristic, data: bytearray) -> None:
        self.journal(f"<- {data.hex(' ')}  ({decodage.decrire_reponse(bytes(data))})")
        if (self._attente is not None and not self._attente.done()
                and len(data) >= 3 and data[0] == 0x80 and data[1] == self._opcode_attendu):
            self._attente.set_result(bytes(data))

    async def envoyer(self, trame: bytes, timeout: float = 3.0) -> int | None:
        """Envoie une commande et renvoie le code résultat (1 = succès), None sans réponse."""
        self._opcode_attendu = trame[0]
        self._attente = asyncio.get_running_loop().create_future()
        nom = decodage.OPCODES.get(trame[0], f"opcode 0x{trame[0]:02X}")
        self.journal(f"-> {trame.hex(' ')}  ({nom})")
        await self.client.write_gatt_char(CONTROL_POINT, trame, response=True)
        try:
            reponse = await asyncio.wait_for(self._attente, timeout)
        except asyncio.TimeoutError:
            self.journal(f"   pas de réponse à {nom} après {timeout:.0f} s")
            return None
        return reponse[2]

    async def demander_controle(self) -> int | None:
        return await self.envoyer(bytes([0x00]))

    async def demarrer(self) -> int | None:
        return await self.envoyer(bytes([0x07]))

    async def arreter(self) -> int | None:
        return await self.envoyer(bytes([0x08, 0x01]))

    async def pause(self) -> int | None:
        return await self.envoyer(bytes([0x08, 0x02]))

    async def vitesse(self, kmh: float) -> int | None:
        """Vitesse cible, uint16 little-endian en 0,01 km/h."""
        return await self.envoyer(bytes([0x02]) + round(kmh * 100).to_bytes(2, "little"))
