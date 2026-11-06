/// Données instantanées envoyées par le tapis (caractéristique Treadmill Data, `0x2ACD`).
///
/// La trame commence par 2 octets de flags, puis les champs présents s'enchaînent dans l'ordre
/// fixé par la norme FTMS. Le décodage suit les flags plutôt que des positions figées : si le
/// tapis change de format, il reste juste, et un écart de longueur est signalé dans
/// ``extraBytes``. Les valeurs « non disponibles » de la norme (`FF…`) donnent `nil`.
public struct TreadmillData: Equatable, Sendable {
    /// Flags bruts annonçant les champs présents.
    public var flags: UInt16
    /// Vitesse instantanée, en km/h.
    public var speedKmh: Double?
    /// Vitesse moyenne, en km/h.
    public var averageSpeedKmh: Double?
    /// Distance totale parcourue, en mètres.
    public var totalDistanceMeters: Int?
    /// Inclinaison, en %.
    public var inclinationPercent: Double?
    /// Angle de rampe, en degrés.
    public var rampAngleDegrees: Double?
    /// Dénivelé positif cumulé, en mètres.
    public var positiveElevationGainMeters: Double?
    /// Dénivelé négatif cumulé, en mètres.
    public var negativeElevationGainMeters: Double?
    /// Allure instantanée, en km/min.
    public var instantaneousPaceKmPerMinute: Double?
    /// Allure moyenne, en km/min.
    public var averagePaceKmPerMinute: Double?
    /// Énergie totale dépensée, en kcal.
    public var totalEnergyKcal: Int?
    /// Énergie dépensée par heure, en kcal.
    public var energyPerHourKcal: Int?
    /// Énergie dépensée par minute, en kcal.
    public var energyPerMinuteKcal: Int?
    /// Fréquence cardiaque, en battements par minute.
    public var heartRateBPM: Int?
    /// Équivalent métabolique (MET).
    public var metabolicEquivalent: Double?
    /// Temps écoulé, en secondes.
    public var elapsedSeconds: Int?
    /// Temps restant, en secondes.
    public var remainingSeconds: Int?
    /// Force sur la bande, en newtons.
    public var forceOnBeltNewtons: Int?
    /// Puissance, en watts.
    public var powerWatts: Int?
    /// Octets en trop (positif) après le dernier champ annoncé par les flags.
    public var extraBytes: Int

    /// Décode une trame `0x2ACD`.
    ///
    /// - Throws: ``FTMSError/truncated(expectedAtLeast:actual:)`` si la trame s'arrête avant
    ///   la fin d'un champ annoncé.
    public init(decoding bytes: some Sequence<UInt8>) throws(FTMSError) {
        var reader = ByteReader(bytes)
        let flags = try reader.uint16()
        self.flags = flags
        extraBytes = 0

        func has(_ bit: Int) -> Bool {
            flags & (1 << bit) != 0
        }

        // Bit 0 « More Data » : la vitesse instantanée est présente quand il vaut 0.
        if !has(0) {
            speedKmh = Double(try reader.uint16()) / 100
        }
        if has(1) {
            averageSpeedKmh = Double(try reader.uint16()) / 100
        }
        if has(2) {
            totalDistanceMeters = Int(try reader.uint24())
        }
        if has(3) {
            inclinationPercent = Self.tenths(try reader.int16())
            rampAngleDegrees = Self.tenths(try reader.int16())
        }
        if has(4) {
            positiveElevationGainMeters = Double(try reader.uint16()) / 10
            negativeElevationGainMeters = Double(try reader.uint16()) / 10
        }
        if has(5) {
            instantaneousPaceKmPerMinute = Double(try reader.uint8()) / 10
        }
        if has(6) {
            averagePaceKmPerMinute = Double(try reader.uint8()) / 10
        }
        if has(7) {
            totalEnergyKcal = Self.available(try reader.uint16())
            energyPerHourKcal = Self.available(try reader.uint16())
            energyPerMinuteKcal = Self.available(try reader.uint8())
        }
        if has(8) {
            heartRateBPM = Int(try reader.uint8())
        }
        if has(9) {
            metabolicEquivalent = Double(try reader.uint8()) / 10
        }
        if has(10) {
            elapsedSeconds = Int(try reader.uint16())
        }
        if has(11) {
            remainingSeconds = Int(try reader.uint16())
        }
        if has(12) {
            forceOnBeltNewtons = Int(try reader.int16())
            powerWatts = Int(try reader.int16())
        }
        extraBytes = reader.remaining
    }

    /// Valeur en dixièmes, `0x7FFF` signifiant « non disponible ».
    private static func tenths(_ raw: Int16) -> Double? {
        raw == .max ? nil : Double(raw) / 10
    }

    /// Entier non signé, la valeur maximale (`FF…`) signifiant « non disponible ».
    private static func available<T: FixedWidthInteger & UnsignedInteger>(_ raw: T) -> Int? {
        raw == .max ? nil : Int(raw)
    }
}
