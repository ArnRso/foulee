public import Foundation

/// Changement de vitesse lu dans les relevés d'une séance.
public struct SpeedChange: Equatable, Sendable {
    /// Secondes écoulées depuis le début de la séance au début du changement.
    public var offsetSeconds: Double
    /// Vitesse avant le changement, en km/h.
    public var fromKmh: Double
    /// Vitesse après le changement, en km/h.
    public var toKmh: Double

    /// Écart de vitesse, positif pour une accélération, en km/h.
    public var deltaKmh: Double {
        ((toKmh - fromKmh) * 100).rounded() / 100
    }
}

extension TreadmillSession {
    /// Écart maximal entre deux relevés d'une même rampe d'accélération ou de décélération.
    ///
    /// Le tapis atteint une nouvelle consigne par paliers successifs : les relevés d'une même
    /// rampe sont regroupés en un seul changement.
    public static let rampGapSeconds = 3.0

    /// Accélérations, décélérations, pauses (vers 0 km/h) et reprises, dans l'ordre.
    ///
    /// Tirés des relevés, ils incluent les changements faits à la télécommande, que le tapis ne
    /// signale pas autrement.
    public var speedChanges: [SpeedChange] {
        var changes: [SpeedChange] = []
        var lastChangeOffset = -Double.infinity
        for (previous, sample) in zip(samples, samples.dropFirst())
        where sample.speedKmh != previous.speedKmh {
            let rising = sample.speedKmh > previous.speedKmh
            if var last = changes.last,
                sample.offsetSeconds - lastChangeOffset <= Self.rampGapSeconds,
                (last.toKmh > last.fromKmh) == rising
            {
                last.toKmh = sample.speedKmh
                changes[changes.count - 1] = last
            } else {
                changes.append(
                    SpeedChange(
                        offsetSeconds: previous.offsetSeconds,
                        fromKmh: previous.speedKmh,
                        toKmh: sample.speedKmh,
                    )
                )
            }
            lastChangeOffset = sample.offsetSeconds
        }
        return changes
    }
}

/// Période de regroupement des statistiques.
public enum StatisticsPeriod: String, CaseIterable, Identifiable, Sendable {
    /// Jour civil.
    case day
    /// Semaine, selon le premier jour de la semaine du calendrier.
    case week
    /// Mois civil.
    case month

    /// Identifiant, pour les listes SwiftUI.
    public var id: Self {
        self
    }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

/// Totaux des séances commencées pendant une période.
public struct PeriodSummary: Equatable, Identifiable, Sendable {
    /// Début de la période.
    public var start: Date
    /// Nombre de séances.
    public var sessionCount = 0
    /// Distance totale, en mètres.
    public var distanceMeters = 0
    /// Temps de marche total, en secondes.
    public var elapsedSeconds = 0
    /// Énergie totale, en kcal.
    public var energyKcal = 0

    /// Crée une période vide.
    public init(start: Date) {
        self.start = start
    }

    /// Identifiant : le début de la période.
    public var id: Date {
        start
    }

    /// Vitesse moyenne sur le temps de marche, en km/h.
    public var averageSpeedKmh: Double {
        elapsedSeconds > 0 ? Double(distanceMeters) / Double(elapsedSeconds) * 3.6 : 0
    }

    mutating func add(_ session: TreadmillSession) {
        sessionCount += 1
        distanceMeters += session.distanceMeters
        elapsedSeconds += session.elapsedSeconds
        energyKcal += session.energyKcal ?? 0
    }
}

/// Regroupement des séances par jour, semaine ou mois.
public enum SessionStatistics {
    /// Totaux des `count` dernières périodes jusqu'à celle qui contient `date`, de la plus
    /// ancienne à la plus récente, périodes vides comprises (pour des graphiques continus).
    public static func summaries(
        of sessions: [TreadmillSession],
        by period: StatisticsPeriod,
        count: Int,
        endingAt date: Date,
        calendar: Calendar,
    ) -> [PeriodSummary] {
        guard count > 0, let last = calendar.dateInterval(of: period.component, for: date)
        else { return [] }
        var summaries = (0..<count).reversed().compactMap { back in
            calendar.date(byAdding: period.component, value: -back, to: last.start)
                .map { PeriodSummary(start: $0) }
        }
        for session in sessions {
            guard
                let start = calendar.dateInterval(of: period.component, for: session.startDate)?
                    .start,
                let index = summaries.firstIndex(where: { $0.start == start })
            else { continue }
            summaries[index].add(session)
        }
        return summaries
    }

    /// Totaux de toutes les séances.
    public static func total(of sessions: [TreadmillSession]) -> PeriodSummary {
        var summary = PeriodSummary(start: sessions.map(\.startDate).min() ?? .distantPast)
        for session in sessions {
            summary.add(session)
        }
        return summary
    }
}
