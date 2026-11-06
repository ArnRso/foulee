"""Décodage des trames FTMS envoyées par le tapis.

Treadmill Data (0x2ACD) : la trame commence par 2 octets de flags (little-endian),
puis les champs présents s'enchaînent dans l'ordre fixé par la norme FTMS.
On décode en suivant les flags plutôt qu'avec des offsets figés : si le tapis
change de format, le décodage reste juste, et une longueur incohérente est signalée.
"""

from dataclasses import dataclass, field


@dataclass
class DonneesTapis:
    flags: int
    vitesse_kmh: float | None = None
    vitesse_moyenne_kmh: float | None = None
    distance_m: int | None = None
    inclinaison_pct: float | None = None
    rampe_deg: float | None = None
    denivele_pos_m: float | None = None
    denivele_neg_m: float | None = None
    allure_km_min: float | None = None
    allure_moyenne_km_min: float | None = None
    kcal: int | None = None
    kcal_heure: int | None = None
    kcal_minute: int | None = None
    frequence_cardiaque: int | None = None
    met: float | None = None
    temps_s: int | None = None
    temps_restant_s: int | None = None
    force_n: int | None = None
    puissance_w: int | None = None
    # Position (début, fin) de chaque champ dans la trame, pour retrouver le brut
    positions: dict[str, tuple[int, int]] = field(default_factory=dict)
    # Octets en trop ou manquants par rapport à ce qu'annoncent les flags
    ecart_longueur: int = 0


class _Lecteur:
    """Lit des entiers little-endian à la suite dans une trame."""

    def __init__(self, data: bytes, debut: int = 0):
        self.data = data
        self.pos = debut

    def lire(self, taille: int, signe: bool = False) -> int:
        valeur = int.from_bytes(self.data[self.pos:self.pos + taille], "little", signed=signe)
        self.pos += taille
        return valeur


def decoder_treadmill_data(data: bytes) -> DonneesTapis:
    """Décode une trame 0x2ACD. Les valeurs « non disponibles » (FF…) donnent None."""
    lecteur = _Lecteur(data)
    flags = lecteur.lire(2)
    d = DonneesTapis(flags=flags)

    def champ(nom: str, taille: int, signe: bool = False, absent: int | None = None) -> int | None:
        debut = lecteur.pos
        valeur = lecteur.lire(taille, signe)
        d.positions[nom] = (debut, lecteur.pos)
        return None if valeur == absent else valeur

    def echelle(valeur: int | None, facteur: float) -> float | None:
        return None if valeur is None else round(valeur * facteur, 2)

    # Bit 0 « More Data » : la vitesse instantanée est présente quand il vaut 0
    if not flags & 0x0001:
        d.vitesse_kmh = echelle(champ("vitesse", 2), 0.01)
    if flags & 0x0002:
        d.vitesse_moyenne_kmh = echelle(champ("vitesse_moyenne", 2), 0.01)
    if flags & 0x0004:
        d.distance_m = champ("distance", 3)
    if flags & 0x0008:
        d.inclinaison_pct = echelle(champ("inclinaison", 2, signe=True, absent=0x7FFF), 0.1)
        d.rampe_deg = echelle(champ("rampe", 2, signe=True, absent=0x7FFF), 0.1)
    if flags & 0x0010:
        d.denivele_pos_m = echelle(champ("denivele_pos", 2), 0.1)
        d.denivele_neg_m = echelle(champ("denivele_neg", 2), 0.1)
    if flags & 0x0020:
        d.allure_km_min = echelle(champ("allure", 1), 0.1)
    if flags & 0x0040:
        d.allure_moyenne_km_min = echelle(champ("allure_moyenne", 1), 0.1)
    if flags & 0x0080:
        d.kcal = champ("kcal", 2, absent=0xFFFF)
        d.kcal_heure = champ("kcal_heure", 2, absent=0xFFFF)
        d.kcal_minute = champ("kcal_minute", 1, absent=0xFF)
    if flags & 0x0100:
        d.frequence_cardiaque = champ("frequence_cardiaque", 1)
    if flags & 0x0200:
        d.met = echelle(champ("met", 1), 0.1)
    if flags & 0x0400:
        d.temps_s = champ("temps", 2)
    if flags & 0x0800:
        d.temps_restant_s = champ("temps_restant", 2)
    if flags & 0x1000:
        d.force_n = champ("force", 2, signe=True)
        d.puissance_w = champ("puissance", 2, signe=True)

    d.ecart_longueur = len(data) - lecteur.pos
    return d


def formater_duree(secondes: int | None) -> str:
    if secondes is None:
        return "--:--"
    heures, reste = divmod(secondes, 3600)
    minutes, sec = divmod(reste, 60)
    return f"{heures}:{minutes:02d}:{sec:02d}" if heures else f"{minutes:02d}:{sec:02d}"


def ligne_etat(d: DonneesTapis) -> str:
    """Ligne d'état compacte pour l'affichage rafraîchi."""

    def val(v: float | int | None, fmt: str) -> str:
        return "--" if v is None else format(v, fmt)

    ligne = (f"Vitesse {val(d.vitesse_kmh, '5.2f')} km/h | "
             f"Distance {val(d.distance_m, '5d')} m | "
             f"Temps {formater_duree(d.temps_s)} | "
             f"{val(d.kcal, '3d')} kcal")
    if d.ecart_longueur:
        ligne += f" | ATTENTION longueur trame {d.ecart_longueur:+d} o"
    return ligne


# Fitness Machine Feature (0x2ACC) : 2 champs de 32 bits
FONCTIONS_MESURE = [
    "vitesse moyenne", "cadence", "distance totale", "inclinaison", "dénivelé",
    "allure", "nombre de pas", "niveau de résistance", "nombre de foulées",
    "énergie dépensée", "fréquence cardiaque", "équivalent métabolique",
    "temps écoulé", "temps restant", "puissance", "force sur la bande", "état utilisateur",
]
FONCTIONS_REGLAGE = [
    "vitesse cible", "inclinaison cible", "résistance cible", "puissance cible",
    "fréquence cardiaque cible", "énergie cible", "nombre de pas cible",
    "nombre de foulées cible", "distance cible", "temps cible",
]


def decoder_fonctions(data: bytes) -> tuple[list[str], list[str]]:
    """Renvoie (mesures fournies, réglages acceptés) d'après 0x2ACC."""
    mesures = int.from_bytes(data[0:4], "little")
    reglages = int.from_bytes(data[4:8], "little")
    return ([nom for i, nom in enumerate(FONCTIONS_MESURE) if mesures >> i & 1],
            [nom for i, nom in enumerate(FONCTIONS_REGLAGE) if reglages >> i & 1])


def decoder_plage_vitesse(data: bytes) -> tuple[float, float, float]:
    """Supported Speed Range (0x2AD4) : (min, max, pas) en km/h."""
    lecteur = _Lecteur(data)
    return tuple(lecteur.lire(2) / 100 for _ in range(3))


# Fitness Machine Control Point (0x2AD9)
OPCODES = {
    0x00: "Request Control",
    0x01: "Reset",
    0x02: "Set Target Speed",
    0x03: "Set Target Inclination",
    0x07: "Start/Resume",
    0x08: "Stop/Pause",
}
RESULTATS = {
    0x01: "succès",
    0x02: "non supporté",
    0x03: "paramètre invalide",
    0x04: "échec",
    0x05: "contrôle non autorisé",
}


def decrire_reponse(data: bytes) -> str:
    """Réponse du Control Point : 80 <opcode demandé> <résultat>."""
    if len(data) < 3 or data[0] != 0x80:
        return f"réponse inattendue : {data.hex(' ')}"
    opcode = OPCODES.get(data[1], f"opcode 0x{data[1]:02X}")
    resultat = RESULTATS.get(data[2], f"code 0x{data[2]:02X}")
    return f"{opcode} → {resultat}"


def decrire_statut(data: bytes) -> str:
    """Fitness Machine Status (0x2ADA) : événement signalé par le tapis."""
    code = data[0]
    if code == 0x01:
        return "réinitialisé"
    if code == 0x02:
        return {0x01: "arrêté par l'utilisateur", 0x02: "mis en pause par l'utilisateur"}.get(
            data[1] if len(data) > 1 else 0, "arrêté/pause")
    if code == 0x03:
        return "arrêté par la clé de sécurité"
    if code == 0x04:
        return "démarré/repris par l'utilisateur"
    if code == 0x05 and len(data) >= 3:
        return f"vitesse cible changée : {int.from_bytes(data[1:3], 'little') / 100:.2f} km/h"
    if code == 0x06 and len(data) >= 3:
        return f"inclinaison cible changée : {int.from_bytes(data[1:3], 'little', signed=True) / 10:.1f} %"
    if code == 0xFF:
        return "CONTRÔLE PERDU"
    return f"statut 0x{code:02X} : {data.hex(' ')}"


ETATS_ENTRAINEMENT = {
    0x00: "autre", 0x01: "inactif", 0x02: "échauffement", 0x03: "intervalles faibles",
    0x04: "intervalles forts", 0x05: "récupération", 0x06: "isométrique",
    0x07: "fréquence cardiaque", 0x08: "test de forme", 0x09: "vitesse hors plage (basse)",
    0x0A: "vitesse hors plage (haute)", 0x0B: "retour au calme", 0x0C: "watts",
    0x0D: "mode manuel", 0x0E: "avant séance", 0x0F: "après séance",
}


def decrire_etat_entrainement(data: bytes) -> str:
    """Training Status (0x2AD3) : octet 0 = flags, octet 1 = état."""
    if len(data) < 2:
        return data.hex(" ")
    return ETATS_ENTRAINEMENT.get(data[1], f"état 0x{data[1]:02X}")
