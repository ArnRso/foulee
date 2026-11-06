/// Règles de sécurité appliquées à toute consigne de vitesse avant de l'envoyer au tapis.
///
/// La consigne est arrondie au pas du tapis, puis bornée entre la vitesse minimale du tapis et
/// le plus petit de deux maximums : celui du tapis et le plafond choisi par l'utilisateur.
public struct SpeedPolicy: Equatable, Sendable {
    /// Plage annoncée par le tapis.
    public var range: SpeedRange
    /// Plafond choisi par l'utilisateur, en km/h.
    public var ceilingKmh: Double
    /// Incrément choisi par l'utilisateur pour les boutons + et −, en km/h.
    public var preferredStepKmh: Double

    /// Crée les règles pour une plage de tapis, un plafond et un incrément (par défaut, le pas
    /// du tapis).
    public init(range: SpeedRange, ceilingKmh: Double, preferredStepKmh: Double = 0) {
        self.range = range
        self.ceilingKmh = ceilingKmh
        self.preferredStepKmh = preferredStepKmh
    }

    /// Vitesse maximale autorisée, en km/h.
    public var maximumKmh: Double {
        max(range.minimumKmh, min(range.maximumKmh, ceilingKmh))
    }

    /// Écart appliqué par les boutons + et − : l'incrément choisi, jamais plus fin que le pas
    /// du tapis, en km/h.
    public var buttonStepKmh: Double {
        max(preferredStepKmh, range.incrementKmh)
    }

    /// Consigne sûre la plus proche de la vitesse demandée.
    public func clamped(_ kmh: Double) -> Double {
        let steps = (kmh / range.incrementKmh).rounded()
        let rounded = (steps * range.incrementKmh * 100).rounded() / 100
        return min(max(rounded, range.minimumKmh), maximumKmh)
    }

    /// Consigne obtenue en appuyant sur + (`direction` = 1) ou − (`direction` = -1).
    public func stepped(from kmh: Double, direction: Int) -> Double {
        clamped(kmh + Double(direction) * buttonStepKmh)
    }
}
