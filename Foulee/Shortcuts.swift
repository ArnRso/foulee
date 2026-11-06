import AppKit
import KeyboardShortcuts

/// Actions de Foulée déclenchables par un raccourci clavier global, réglable dans les Réglages.
///
/// Les raccourcis fonctionnent quelle que soit l'app au premier plan, sans autorisation
/// d'accessibilité (KeyboardShortcuts s'appuie sur les raccourcis globaux de Carbon).
enum ShortcutAction: CaseIterable, Identifiable {
    case togglePause
    case speedUp
    case speedDown
    case toggleSlowSpeed
    case stop

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .togglePause: "Démarrer / pause"
        case .speedUp: "Accélérer"
        case .speedDown: "Ralentir"
        case .toggleSlowSpeed: "Bascule vitesse lente"
        case .stop: "Arrêter"
        }
    }

    var name: KeyboardShortcuts.Name {
        switch self {
        case .togglePause: .togglePause
        case .speedUp: .speedUp
        case .speedDown: .speedDown
        case .toggleSlowSpeed: .toggleSlowSpeed
        case .stop: .stopBelt
        }
    }

    @MainActor
    func perform(on treadmill: TreadmillController) async {
        guard treadmill.hasControl else {
            NSSound.beep()
            return
        }
        switch self {
        case .togglePause: await treadmill.togglePause()
        case .speedUp: await treadmill.changeSpeed(direction: 1)
        case .speedDown: await treadmill.changeSpeed(direction: -1)
        case .toggleSlowSpeed: await treadmill.toggleSlowSpeed()
        case .stop: await treadmill.stopBelt()
        }
    }

    /// Écoute tous les raccourcis jusqu'à la fermeture de l'app.
    @MainActor
    static func listen(for treadmill: TreadmillController) {
        for action in allCases {
            Task {
                for await _ in KeyboardShortcuts.events(.keyDown, for: action.name) {
                    await action.perform(on: treadmill)
                }
            }
        }
    }
}

// Raccourcis par défaut : ⌃⌥ suivi d'une touche, rarement utilisé par d'autres apps.
extension KeyboardShortcuts.Name {
    static let togglePause = Self(
        "basculerPause",
        default: .init(.space, modifiers: [.control, .option]),
    )
    static let speedUp = Self(
        "accelerer",
        default: .init(.upArrow, modifiers: [.control, .option]),
    )
    static let speedDown = Self(
        "ralentir",
        default: .init(.downArrow, modifiers: [.control, .option]),
    )
    static let toggleSlowSpeed = Self(
        "basculerVitesseLente",
        default: .init(.l, modifiers: [.control, .option]),
    )
    static let stopBelt = Self(
        "arreter",
        default: .init(.s, modifiers: [.control, .option]),
    )
}
