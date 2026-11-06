import Foundation
import Observation
import ServiceManagement

/// Ouverture de Foulée à la connexion (Réglages Système › Général › Ouverture).
@MainActor
@Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status
    private(set) var error: String?

    var isEnabled: Bool {
        get { status == .enabled || status == .requiresApproval }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                error = nil
            } catch {
                self.error = error.localizedDescription
            }
            refresh()
        }
    }

    /// L'utilisateur peut changer l'autorisation dans Réglages Système : relu à l'ouverture du menu.
    func refresh() {
        status = SMAppService.mainApp.status
    }
}
