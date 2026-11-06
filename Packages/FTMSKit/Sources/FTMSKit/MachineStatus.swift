/// Événement signalé par le tapis (caractéristique Fitness Machine Status, `0x2ADA`).
///
/// Sur le tapis testé, ces notifications n'arrivent qu'aux changements d'état (démarrage,
/// pause, arrêt), pas aux changements de vitesse.
public enum MachineStatus: Equatable, Sendable {
    /// Tapis réinitialisé.
    case reset
    /// Arrêté par l'utilisateur (télécommande ou commande Stop).
    case stoppedByUser
    /// Mis en pause par l'utilisateur.
    case pausedByUser
    /// Arrêté par la clé de sécurité.
    case stoppedBySafetyKey
    /// Démarré ou repris par l'utilisateur.
    case startedOrResumedByUser
    /// Vitesse cible modifiée, en km/h.
    case targetSpeedChanged(kmh: Double)
    /// Inclinaison cible modifiée, en %.
    case targetInclinationChanged(percent: Double)
    /// Le contrôle a été repris par un autre appareil ou par le tapis.
    case controlPermissionLost
    /// Autre événement de la norme, gardé en brut.
    case other(opCode: UInt8, parameters: [UInt8])

    /// Décode une notification de `0x2ADA`.
    ///
    /// - Throws: ``FTMSError`` si la trame est vide ou s'arrête avant la fin d'un paramètre.
    public init(decoding bytes: some Sequence<UInt8>) throws(FTMSError) {
        var reader = ByteReader(bytes)
        let opCode = try reader.uint8()
        switch opCode {
        case 0x01:
            self = .reset
        case 0x02:
            self = reader.remaining > 0 && reader.bytes[1] == 0x02 ? .pausedByUser : .stoppedByUser
        case 0x03:
            self = .stoppedBySafetyKey
        case 0x04:
            self = .startedOrResumedByUser
        case 0x05:
            self = .targetSpeedChanged(kmh: Double(try reader.uint16()) / 100)
        case 0x06:
            self = .targetInclinationChanged(percent: Double(try reader.int16()) / 10)
        case 0xFF:
            self = .controlPermissionLost
        default:
            self = .other(opCode: opCode, parameters: Array(reader.bytes.dropFirst()))
        }
    }

    /// Le tapis repart de sa vitesse minimale : une vitesse cible antérieure ne vaut plus.
    public var resetsTargetSpeed: Bool {
        switch self {
        case .reset, .stoppedByUser, .pausedByUser, .stoppedBySafetyKey, .startedOrResumedByUser:
            true
        case .targetSpeedChanged, .targetInclinationChanged, .controlPermissionLost, .other:
            false
        }
    }

    /// Description en français, pour l'interface et les journaux.
    public var description: String {
        switch self {
        case .reset: "réinitialisé"
        case .stoppedByUser: "arrêté par l'utilisateur"
        case .pausedByUser: "mis en pause par l'utilisateur"
        case .stoppedBySafetyKey: "arrêté par la clé de sécurité"
        case .startedOrResumedByUser: "démarré ou repris par l'utilisateur"
        case .targetSpeedChanged(let kmh): "vitesse cible changée : \(kmh) km/h"
        case .targetInclinationChanged(let percent): "inclinaison cible changée : \(percent) %"
        case .controlPermissionLost: "contrôle perdu"
        case .other(let opCode, let parameters):
            "statut 0x" + String(opCode, radix: 16) + " " + hexString(parameters)
        }
    }
}

/// État d'entraînement (caractéristique Training Status, `0x2AD3`).
public struct TrainingStatus: Equatable, Sendable {
    /// Code d'état de la norme (`0x0D` = mode manuel, `0x01` = inactif…).
    public var code: UInt8

    /// Décode une notification ou une lecture de `0x2AD3` : octet 0 = flags, octet 1 = état.
    ///
    /// - Throws: ``FTMSError`` si la trame fait moins de 2 octets.
    public init(decoding bytes: some Sequence<UInt8>) throws(FTMSError) {
        var reader = ByteReader(bytes)
        _ = try reader.uint8()
        code = try reader.uint8()
    }

    /// Description en français.
    public var description: String {
        switch code {
        case 0x00: "autre"
        case 0x01: "inactif"
        case 0x02: "échauffement"
        case 0x03: "intervalles faibles"
        case 0x04: "intervalles forts"
        case 0x05: "récupération"
        case 0x06: "isométrique"
        case 0x07: "fréquence cardiaque"
        case 0x08: "test de forme"
        case 0x09: "vitesse trop basse"
        case 0x0A: "vitesse trop haute"
        case 0x0B: "retour au calme"
        case 0x0C: "watts"
        case 0x0D: "mode manuel"
        case 0x0E: "avant séance"
        case 0x0F: "après séance"
        default: "état 0x" + String(code, radix: 16)
        }
    }
}
