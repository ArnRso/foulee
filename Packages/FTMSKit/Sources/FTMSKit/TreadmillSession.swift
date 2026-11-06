public import Foundation

/// Séance de marche enregistrée : totaux et relevés seconde par seconde, enregistrés en JSON.
public struct TreadmillSession: Codable, Equatable, Identifiable, Sendable {
    /// Relevé du tapis à un instant de la séance.
    public struct Sample: Codable, Equatable, Sendable {
        /// Secondes écoulées depuis le début de la séance, selon l'horloge du Mac.
        public var offsetSeconds: Double
        /// Vitesse, en km/h.
        public var speedKmh: Double
        /// Distance depuis le début de la séance, en mètres.
        public var distanceMeters: Int
        /// Énergie depuis le début de la séance, en kcal.
        public var energyKcal: Int?
        /// Temps de marche compté par le tapis (pauses exclues), en secondes.
        public var elapsedSeconds: Int?
    }

    /// Événement survenu pendant la séance.
    ///
    /// Les changements de vitesse faits à la télécommande ne sont pas signalés par le tapis :
    /// ils se lisent dans les relevés, voir ``speedChanges``.
    public struct Event: Codable, Equatable, Sendable {
        /// Nature de l'événement.
        public enum Kind: String, Codable, Sendable {
            /// Bande démarrée ou reprise après une pause.
            case started
            /// Bande mise en pause.
            case paused
            /// Bande arrêtée.
            case stopped
            /// Vitesse cible envoyée par Foulée.
            case targetSpeed
            /// Connexion Bluetooth perdue.
            case connectionLost
            /// Connexion Bluetooth retrouvée.
            case reconnected
        }

        /// Secondes écoulées depuis le début de la séance.
        public var offsetSeconds: Double
        /// Nature de l'événement.
        public var kind: Kind
        /// Vitesse associée (consigne pour ``Kind/targetSpeed``), en km/h.
        public var speedKmh: Double?
    }

    /// Version du format, à incrémenter si la structure du fichier change.
    ///
    /// Version 2 : ajout de ``events`` (absent des fichiers en version 1).
    public static let formatVersion = 2

    /// Version du format de ce fichier.
    public var formatVersion = Self.formatVersion
    /// Identifiant unique de la séance.
    public var id = UUID()
    /// Nom Bluetooth du tapis.
    public var deviceName: String?
    /// Début de la séance (premier relevé avec la bande en mouvement).
    public var startDate: Date
    /// Fin de la séance (dernier relevé).
    public var endDate: Date
    /// Temps de marche compté par le tapis (pauses exclues), en secondes.
    public var elapsedSeconds: Int
    /// Distance totale, en mètres.
    public var distanceMeters: Int
    /// Énergie totale, en kcal, si le tapis la fournit.
    public var energyKcal: Int?
    /// Vitesse maximale relevée, en km/h.
    public var maximumSpeedKmh: Double
    /// La séance s'est terminée par une perte de connexion ou la fermeture de l'app, pas par un
    /// arrêt du tapis : ses totaux s'arrêtent au dernier relevé reçu.
    public var isInterrupted = false
    /// Relevés seconde par seconde.
    public var samples: [Sample] = []
    /// Démarrages, pauses, arrêts, consignes de vitesse et pertes de connexion.
    public var events: [Event] = []

    /// Vitesse moyenne sur le temps de marche, en km/h.
    public var averageSpeedKmh: Double {
        elapsedSeconds > 0 ? Double(distanceMeters) / Double(elapsedSeconds) * 3.6 : 0
    }

    /// Une séance trop courte (bande lancée puis aussitôt arrêtée) n'est pas conservée.
    public var isWorthKeeping: Bool {
        distanceMeters >= 10 || elapsedSeconds >= 60
    }
}

// Décodage écrit à la main pour relire les fichiers des versions précédentes du format.
extension TreadmillSession {
    /// Relit une séance enregistrée, quelle que soit la version de son format.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        id = try container.decode(UUID.self, forKey: .id)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        elapsedSeconds = try container.decode(Int.self, forKey: .elapsedSeconds)
        distanceMeters = try container.decode(Int.self, forKey: .distanceMeters)
        energyKcal = try container.decodeIfPresent(Int.self, forKey: .energyKcal)
        maximumSpeedKmh = try container.decode(Double.self, forKey: .maximumSpeedKmh)
        isInterrupted = try container.decode(Bool.self, forKey: .isInterrupted)
        samples = try container.decode([Sample].self, forKey: .samples)
        events = try container.decodeIfPresent([Event].self, forKey: .events) ?? []
    }
}

/// Découpe le flux du tapis en séances.
///
/// Une séance commence au premier relevé où la bande tourne, survit aux pauses et aux pertes de
/// connexion, et se termine quand le tapis signale un arrêt ou remet ses compteurs à zéro.
public struct SessionRecorder: Sendable {
    /// Recul toléré du temps écoulé avant de considérer que le tapis a remis ses compteurs à zéro.
    private static let counterResetTolerance = 5

    /// Séance en cours, `nil` entre deux séances.
    public private(set) var current: TreadmillSession?

    /// Crée un enregistreur sans séance en cours.
    public init() {}

    /// Ajoute un relevé du tapis.
    ///
    /// - Returns: la séance précédente si ce relevé montre que le tapis a remis ses compteurs à
    ///   zéro sans qu'un arrêt ait été signalé.
    public mutating func record(
        _ data: TreadmillData,
        at date: Date,
        deviceName: String?,
    ) -> TreadmillSession? {
        guard let speed = data.speedKmh, let distance = data.totalDistanceMeters else { return nil }
        var finished: TreadmillSession?
        if let session = current, let elapsed = data.elapsedSeconds,
            elapsed + Self.counterResetTolerance < session.elapsedSeconds
        {
            finished = finish(interrupted: false)
        }
        if current == nil {
            guard speed > 0 else { return finished }
            // Séance déjà commencée avant la connexion (télécommande) : on la date d'après le
            // temps écoulé compté par le tapis.
            let startDate = date.addingTimeInterval(-Double(data.elapsedSeconds ?? 0))
            current = TreadmillSession(
                deviceName: deviceName,
                startDate: startDate,
                endDate: date,
                elapsedSeconds: 0,
                distanceMeters: 0,
                maximumSpeedKmh: 0,
            )
        }
        update(with: data, speed: speed, distance: distance, at: date)
        return finished
    }

    /// Prend en compte un événement du tapis.
    ///
    /// - Returns: la séance terminée si l'événement est un arrêt.
    public mutating func record(_ status: MachineStatus, at date: Date) -> TreadmillSession? {
        switch status {
        case .stoppedByUser, .stoppedBySafetyKey, .reset:
            note(.stopped, at: date)
            return finish(interrupted: false)
        case .pausedByUser:
            note(.paused, at: date)
        case .startedOrResumedByUser:
            note(.started, at: date)
        case .targetSpeedChanged, .targetInclinationChanged, .controlPermissionLost, .other:
            break
        }
        return nil
    }

    /// Ajoute un événement à la séance en cours ; sans séance en cours, il est ignoré.
    public mutating func note(
        _ kind: TreadmillSession.Event.Kind,
        speedKmh: Double? = nil,
        at date: Date,
    ) {
        guard var session = current else { return }
        session.events.append(
            TreadmillSession.Event(
                offsetSeconds: date.timeIntervalSince(session.startDate),
                kind: kind,
                speedKmh: speedKmh,
            )
        )
        current = session
    }

    /// Termine la séance en cours sans attendre d'arrêt du tapis (fermeture de l'app).
    public mutating func finish(interrupted: Bool) -> TreadmillSession? {
        defer { current = nil }
        guard var session = current else { return nil }
        session.isInterrupted = interrupted
        return session
    }

    private mutating func update(
        with data: TreadmillData,
        speed: Double,
        distance: Int,
        at date: Date,
    ) {
        guard var session = current else { return }
        session.endDate = date
        session.distanceMeters = max(session.distanceMeters, distance)
        session.elapsedSeconds = max(session.elapsedSeconds, data.elapsedSeconds ?? 0)
        if let energy = data.totalEnergyKcal {
            session.energyKcal = max(session.energyKcal ?? 0, energy)
        }
        session.maximumSpeedKmh = max(session.maximumSpeedKmh, speed)
        session.samples.append(
            TreadmillSession.Sample(
                offsetSeconds: date.timeIntervalSince(session.startDate),
                speedKmh: speed,
                distanceMeters: distance,
                energyKcal: data.totalEnergyKcal,
                elapsedSeconds: data.elapsedSeconds,
            )
        )
        current = session
    }
}
