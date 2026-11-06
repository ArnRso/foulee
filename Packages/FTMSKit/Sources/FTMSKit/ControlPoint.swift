/// Commande envoyée au tapis sur le Fitness Machine Control Point (`0x2AD9`).
///
/// Séquence validée sur le tapis : s'abonner aux indications de `0x2AD9`, envoyer
/// ``requestControl``, puis les autres commandes. Chaque commande reçoit une réponse
/// ``ControlPointResponse``.
public enum ControlPointCommand: Equatable, Sendable {
    /// Demande le contrôle du tapis (préalable à toute autre commande).
    case requestControl
    /// Remet le tapis dans son état initial.
    case reset
    /// Vitesse cible, en km/h (résolution 0,01 km/h).
    case setTargetSpeed(kmh: Double)
    /// Démarre ou reprend après une pause.
    case startOrResume
    /// Arrête la séance (distance et temps remis à zéro par le tapis).
    case stop
    /// Met en pause (distance et temps conservés).
    case pause

    /// Code d'opération FTMS de la commande.
    public var opCode: UInt8 {
        switch self {
        case .requestControl: 0x00
        case .reset: 0x01
        case .setTargetSpeed: 0x02
        case .startOrResume: 0x07
        case .stop, .pause: 0x08
        }
    }

    /// Trame à écrire sur `0x2AD9`.
    public var bytes: [UInt8] {
        switch self {
        case .requestControl, .reset, .startOrResume:
            [opCode]
        case .setTargetSpeed(let kmh):
            [opCode] + Self.littleEndian(UInt16(clamping: Int((kmh * 100).rounded())))
        case .stop:
            [opCode, 0x01]
        case .pause:
            [opCode, 0x02]
        }
    }

    private static func littleEndian(_ value: UInt16) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
    }

    /// Nom lisible d'un code d'opération, pour les journaux.
    public static func name(ofOpCode opCode: UInt8) -> String {
        switch opCode {
        case 0x00: "Request Control"
        case 0x01: "Reset"
        case 0x02: "Set Target Speed"
        case 0x03: "Set Target Inclination"
        case 0x07: "Start/Resume"
        case 0x08: "Stop/Pause"
        default: "opcode 0x" + String(opCode, radix: 16, uppercase: true)
        }
    }
}

/// Résultat d'une commande, renvoyé par le tapis.
public enum ControlPointResult: UInt8, Equatable, Sendable {
    /// Commande exécutée.
    case success = 0x01
    /// Commande non supportée par le tapis.
    case notSupported = 0x02
    /// Paramètre hors des bornes acceptées.
    case invalidParameter = 0x03
    /// Échec de la commande.
    case failed = 0x04
    /// Le contrôle n'a pas été obtenu (Request Control manquant ou refusé).
    case controlNotPermitted = 0x05

    /// Description en français, pour l'interface et les journaux.
    public var description: String {
        switch self {
        case .success: "succès"
        case .notSupported: "non supporté"
        case .invalidParameter: "paramètre invalide"
        case .failed: "échec"
        case .controlNotPermitted: "contrôle non autorisé"
        }
    }
}

/// Réponse du tapis à une commande : `80 <opcode demandé> <résultat>`.
public struct ControlPointResponse: Equatable, Sendable {
    /// Code d'opération de la commande à laquelle le tapis répond.
    public var requestOpCode: UInt8
    /// Résultat, `nil` si le code renvoyé est inconnu de la norme.
    public var result: ControlPointResult?
    /// Code résultat brut.
    public var rawResult: UInt8

    /// Décode une indication de `0x2AD9`.
    ///
    /// - Throws: ``FTMSError`` si la trame n'est pas une réponse (`0x80`) complète.
    public init(decoding bytes: some Sequence<UInt8>) throws(FTMSError) {
        var reader = ByteReader(bytes)
        guard try reader.uint8() == 0x80 else {
            throw .malformed("réponse sans code 0x80 : " + hexString(reader.bytes))
        }
        requestOpCode = try reader.uint8()
        rawResult = try reader.uint8()
        result = ControlPointResult(rawValue: rawResult)
    }

    /// Description lisible, par exemple « Set Target Speed → succès ».
    public var description: String {
        let name = ControlPointCommand.name(ofOpCode: requestOpCode)
        let outcome = result?.description ?? "code 0x" + String(rawResult, radix: 16)
        return name + " → " + outcome
    }
}
