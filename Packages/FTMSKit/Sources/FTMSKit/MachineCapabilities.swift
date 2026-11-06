/// Fonctions annoncées par le tapis (caractéristique Fitness Machine Feature, `0x2ACC`).
public struct MachineFeatures: Equatable, Sendable {
    /// Bits des mesures fournies (premier champ de 32 bits).
    public var measurementBits: UInt32
    /// Bits des réglages acceptés (second champ de 32 bits).
    public var targetSettingBits: UInt32

    private static let measurementNames = [
        "vitesse moyenne", "cadence", "distance totale", "inclinaison", "dénivelé", "allure",
        "nombre de pas", "niveau de résistance", "nombre de foulées", "énergie dépensée",
        "fréquence cardiaque", "équivalent métabolique", "temps écoulé", "temps restant",
        "puissance", "force sur la bande", "état utilisateur",
    ]

    private static let targetSettingNames = [
        "vitesse cible", "inclinaison cible", "résistance cible", "puissance cible",
        "fréquence cardiaque cible", "énergie cible", "nombre de pas cible",
        "nombre de foulées cible", "distance cible", "temps cible",
    ]

    /// Décode une lecture de `0x2ACC` (8 octets).
    ///
    /// - Throws: ``FTMSError`` si la trame fait moins de 8 octets.
    public init(decoding bytes: some Sequence<UInt8>) throws(FTMSError) {
        var reader = ByteReader(bytes)
        measurementBits = try reader.uint32()
        targetSettingBits = try reader.uint32()
    }

    /// Le tapis accepte une vitesse cible (commande Set Target Speed).
    public var supportsTargetSpeed: Bool {
        targetSettingBits & 1 != 0
    }

    /// Noms des mesures fournies, en français.
    public var measurements: [String] {
        Self.names(Self.measurementNames, for: measurementBits)
    }

    /// Noms des réglages acceptés, en français.
    public var targetSettings: [String] {
        Self.names(Self.targetSettingNames, for: targetSettingBits)
    }

    private static func names(_ names: [String], for bits: UInt32) -> [String] {
        names.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element)
    }
}

/// Plage de vitesse acceptée par le tapis (caractéristique Supported Speed Range, `0x2AD4`).
public struct SpeedRange: Equatable, Sendable {
    /// Vitesse minimale, en km/h.
    public var minimumKmh: Double
    /// Vitesse maximale, en km/h.
    public var maximumKmh: Double
    /// Plus petit écart de vitesse accepté, en km/h.
    public var incrementKmh: Double

    /// Crée une plage à partir de ses bornes.
    public init(minimumKmh: Double, maximumKmh: Double, incrementKmh: Double) {
        self.minimumKmh = minimumKmh
        self.maximumKmh = maximumKmh
        self.incrementKmh = incrementKmh
    }

    /// Décode une lecture de `0x2AD4` : trois `uint16` en 0,01 km/h (min, max, pas).
    ///
    /// - Throws: ``FTMSError`` si la trame fait moins de 6 octets ou si la plage est incohérente.
    public init(decoding bytes: some Sequence<UInt8>) throws(FTMSError) {
        var reader = ByteReader(bytes)
        minimumKmh = Double(try reader.uint16()) / 100
        maximumKmh = Double(try reader.uint16()) / 100
        incrementKmh = Double(try reader.uint16()) / 100
        guard minimumKmh < maximumKmh, incrementKmh > 0 else {
            throw .malformed("plage de vitesse incohérente : " + hexString(reader.bytes))
        }
    }
}
